#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Catch errors in pipelines

# ---------------------------
# Function Definitions
# ---------------------------

# Function to display usage instructions
usage() {
  echo "Usage: $0 [--region <AWS_REGION>]"
  echo "  --region         AWS region of deployment (default: us-east-2)"
  exit 1
}

# Function to check if a command exists
check_command() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: '$cmd' is not installed. Please install it and retry."
    exit 1
  fi
}

# Function to configure AWS CLI if credentials are missing
configure_aws_cli() {
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS credentials not found in environment variables."
    echo "Configuring AWS CLI..."
    aws configure
  else
    echo "AWS credentials found in environment variables."
  fi
}

# Function to delete ECS service if it exists
delete_ecs_service() {
  echo "Deleting ECS Service '$SERVICE_NAME'..."

  # Check if service exists
  SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text)

  if [ "$SERVICE_EXISTS" != "None" ] && [ -n "$SERVICE_EXISTS" ]; then
    # Get the current status of the service
    SERVICE_STATUS=$(aws ecs describe-services \
      --cluster "$CLUSTER_NAME" \
      --services "$SERVICE_NAME" \
      --region "$AWS_REGION" \
      --query 'services[0].status' \
      --output text)

    echo "Current ECS Service Status: $SERVICE_STATUS"

    if [ "$SERVICE_STATUS" == "ACTIVE" ]; then
      # Update desired count to 0 to stop running tasks
      echo "Updating desired count to 0 to stop running tasks..."
      aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 0 \
        --region "$AWS_REGION"

      # Wait until the service is stable
      echo "Waiting for service to stabilize..."
      aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION"

      # Delete the service
      echo "Deleting ECS Service '$SERVICE_NAME'..."
      aws ecs delete-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --region "$AWS_REGION"
      echo "ECS Service '$SERVICE_NAME' deleted."
    else
      echo "ECS Service '$SERVICE_NAME' is not ACTIVE (current status: $SERVICE_STATUS). Attempting to delete with --force flag..."
      # Attempt to delete the service with --force
      aws ecs delete-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --force \
        --region "$AWS_REGION"
      echo "ECS Service '$SERVICE_NAME' deleted with --force flag."
    fi
  else
    echo "ECS Service '$SERVICE_NAME' does not exist. Skipping deletion."
  fi
}

# Function to deregister ECS task definitions
deregister_task_definitions() {
  echo "Deregistering ECS Task Definitions for family '$TASK_FAMILY'..."

  # Get all task definition ARNs for the family in JSON format
  TASK_DEFINITION_ARNS_JSON=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_FAMILY" \
    --status ACTIVE \
    --sort DESC \
    --region "$AWS_REGION" \
    --output json)

  # Extract ARNs using jq
  TASK_DEFINITION_ARNS=$(echo "$TASK_DEFINITION_ARNS_JSON" | jq -r '.taskDefinitionArns[]')

  # Debug: Print retrieved task definition ARNs
  echo "Retrieved Task Definition ARNs:"
  echo "$TASK_DEFINITION_ARNS"

  if [ -z "$TASK_DEFINITION_ARNS" ]; then
    echo "No active task definitions found for family '$TASK_FAMILY'. Skipping deregistration."
    return
  fi

  # Deregister each task definition
  for TASK_DEF_ARN in $TASK_DEFINITION_ARNS; do
    # Debug: Print the task definition ARN being deregistered
    echo "Deregistering task definition '$TASK_DEF_ARN'..."
    aws ecs deregister-task-definition \
      --task-definition "$TASK_DEF_ARN" \
      --region "$AWS_REGION"
    echo "Task definition '$TASK_DEF_ARN' deregistered."
  done
}

# Function to delete ECS cluster if it exists
delete_ecs_cluster() {
  echo "Deleting ECS Cluster '$CLUSTER_NAME'..."

  # Check if cluster exists
  CLUSTER_EXISTS=$(aws ecs describe-clusters \
    --clusters "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'clusters[0].clusterName' \
    --output text)

  if [ "$CLUSTER_EXISTS" != "None" ] && [ -n "$CLUSTER_EXISTS" ]; then
    # Delete the cluster
    aws ecs delete-cluster \
      --cluster "$CLUSTER_NAME" \
      --region "$AWS_REGION"
    echo "ECS Cluster '$CLUSTER_NAME' deleted."
  else
    echo "ECS Cluster '$CLUSTER_NAME' does not exist. Skipping deletion."
  fi
}

# Function to delete Security Group if it exists
delete_security_group() {
  echo "Deleting Security Group '$SECURITY_GROUP_NAME'..."

  # Get Security Group ID
  SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SECURITY_GROUP_NAME" Name=vpc-id,Values="$DEFAULT_VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text --region "$AWS_REGION")

  if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
    echo "Security Group '$SECURITY_GROUP_NAME' does not exist. Skipping deletion."
    return
  fi

  # Check if the security group is in use
  IN_USE=$(aws ec2 describe-network-interfaces \
    --filters "Name=group-id,Values=$SECURITY_GROUP_ID" \
    --query 'NetworkInterfaces' \
    --output json --region "$AWS_REGION" | jq length)

  if [ "$IN_USE" -gt 0 ]; then
    echo "Security Group '$SECURITY_GROUP_NAME' is in use by other resources. Skipping deletion."
  else
    # Delete the security group
    aws ec2 delete-security-group \
      --group-id "$SECURITY_GROUP_ID" \
      --region "$AWS_REGION"
    echo "Security Group '$SECURITY_GROUP_NAME' deleted."
  fi
}

# Function to delete ECR repository if it exists
delete_ecr_repository() {
  echo "Deleting ECR Repository '$REPO_NAME'..."

  # Check if repository exists
  REPO_EXISTS=$(aws ecr describe-repositories \
    --repository-names "$REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'repositories[0].repositoryName' \
    --output text 2>/dev/null || echo "None")

  if [ "$REPO_EXISTS" == "None" ]; then
    echo "ECR Repository '$REPO_NAME' does not exist. Skipping deletion."
    return
  fi

  # Delete all images in the repository
  echo "Deleting all images in ECR Repository '$REPO_NAME'..."
  IMAGE_DIGESTS=$(aws ecr list-images \
    --repository-name "$REPO_NAME" \
    --filter "tagStatus=ANY" \
    --query 'imageIds[*].imageDigest' \
    --output text --region "$AWS_REGION")

  if [ -n "$IMAGE_DIGESTS" ]; then
    for DIGEST in $IMAGE_DIGESTS; do
      echo "Deleting image with digest '$DIGEST'..."
      aws ecr batch-delete-image \
        --repository-name "$REPO_NAME" \
        --image-ids imageDigest="$DIGEST" \
        --region "$AWS_REGION"
      echo "Image with digest '$DIGEST' deleted."
    done
  else
    echo "No images found in ECR Repository '$REPO_NAME'."
  fi

  # Delete the repository
  aws ecr delete-repository \
    --repository-name "$REPO_NAME" \
    --force \
    --region "$AWS_REGION"
  echo "ECR Repository '$REPO_NAME' deleted."
}

# Function to detach and delete IAM role
delete_iam_role() {
  echo "Deleting IAM Role '$ROLE_NAME'..."

  # Check if role exists
  ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" --output text 2>/dev/null || echo "None")

  if [ "$ROLE_EXISTS" == "None" ]; then
    echo "IAM Role '$ROLE_NAME' does not exist. Skipping deletion."
    return
  fi

  # Detach all policies attached to the role
  echo "Detaching policies from IAM Role '$ROLE_NAME'..."
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text --region "$AWS_REGION")

  for POLICY in $ATTACHED_POLICIES; do
    echo "Detaching policy '$POLICY' from role '$ROLE_NAME'..."
    aws iam detach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn "$POLICY" \
      --region "$AWS_REGION"
    echo "Policy '$POLICY' detached."
  done

  # Delete the role
  aws iam delete-role \
    --role-name "$ROLE_NAME" \
    --region "$AWS_REGION"
  echo "IAM Role '$ROLE_NAME' deleted."
}

# Function to delete CloudWatch Logs group
delete_cloudwatch_logs() {
  echo "Deleting CloudWatch Logs Group '/ecs/$TASK_FAMILY'..."

  LOG_GROUP_NAME="/ecs/$TASK_FAMILY"

  # Check if log group exists
  LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP_NAME" \
    --query 'logGroups[?logGroupName==`'"$LOG_GROUP_NAME"'`].logGroupName' \
    --output text --region "$AWS_REGION" || echo "None")

  if [ "$LOG_GROUP_EXISTS" == "$LOG_GROUP_NAME" ]; then
    aws logs delete-log-group \
      --log-group-name "$LOG_GROUP_NAME" \
      --region "$AWS_REGION"
    echo "CloudWatch Logs Group '$LOG_GROUP_NAME' deleted."
  else
    echo "CloudWatch Logs Group '$LOG_GROUP_NAME' does not exist. Skipping deletion."
  fi
}

# ---------------------------
# Main Script Execution
# ---------------------------

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --region) AWS_REGION="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# Set default region to us-east-2 if not provided
AWS_REGION="${AWS_REGION:-us-east-2}"

# Check for required commands
for cmd in aws docker jq; do
  check_command "$cmd"
done

# Configure AWS CLI if necessary
configure_aws_cli

# Retrieve AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --region "$AWS_REGION")
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Define variables (must match the deployment script)
REPO_NAME="patient-survival-prediction-repo"
CLUSTER_NAME="patient-survival-cluster"
TASK_FAMILY="patient-survival-task-family"
CONTAINER_NAME="patient-survival-container"
ROLE_NAME="ecsTaskExecutionRole"
SERVICE_NAME="patient-survival-service"
CONTAINER_PORT=80  # Must match deployment script
SECURITY_GROUP_NAME="ecs-security-group"
DESCRIPTION="Security group for ECS service"

# Retrieve Default VPC ID
echo "Retrieving Default VPC ID..."
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region "$AWS_REGION")

if [ "$DEFAULT_VPC_ID" == "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
  echo "Error: No default VPC found in region '$AWS_REGION'. Please ensure a default VPC exists."
  exit 1
fi

echo "Default VPC ID: $DEFAULT_VPC_ID"

# Execute cleanup steps
delete_ecs_service
deregister_task_definitions
delete_ecs_cluster
delete_security_group
delete_ecr_repository
delete_cloudwatch_logs
delete_iam_role

echo "Cleanup complete. All resources associated with the Patient Survival Prediction application have been removed."