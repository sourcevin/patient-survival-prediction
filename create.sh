#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Catch errors in pipelines

# ---------------------------
# Function Definitions
# ---------------------------

# Function to display usage instructions
usage() {
  echo "Usage: $0 [--region <AWS_REGION>] [--desired-count <COUNT>]"
  echo "  --region         AWS region to deploy (default: us-east-2)"
  echo "  --desired-count  Number of desired task instances (default: 1)"
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

# Function to create ECR repository if it doesn't exist
create_ecr_repository() {
  echo "Creating ECR repository..."
  if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" &> /dev/null; then
    aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION"
    echo "ECR repository '$REPO_NAME' created."
  else
    echo "ECR repository '$REPO_NAME' already exists."
  fi
}

# Function to build and push Docker image to ECR
build_and_push_docker_image() {
  echo "Building Docker image..."
  if ! docker build -t "$REPO_NAME:latest" .; then
    echo "Error: Docker build failed."
    exit 1
  fi

  echo "Logging into ECR..."
  if ! aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"; then
    echo "Error: ECR login failed."
    exit 1
  fi

  echo "Tagging Docker image..."
  if ! docker tag "$REPO_NAME:latest" "$IMAGE_NAME"; then
    echo "Error: Docker tagging failed."
    exit 1
  fi

  echo "Pushing Docker image to ECR..."
  if ! docker push "$IMAGE_NAME"; then
    echo "Error: Docker push failed."
    exit 1
  fi

  echo "Docker image pushed successfully as '$IMAGE_NAME'."
}

# Function to create IAM role for ECS task execution if it doesn't exist
create_iam_role() {
  echo "Creating IAM role for ECS task execution..."
  if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "ecs-tasks.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }'
    echo "IAM role '$ROLE_NAME' created."
    
    echo "Attaching policy to IAM role..."
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    echo "Policy attached to IAM role '$ROLE_NAME'."
  else
    echo "IAM role '$ROLE_NAME' already exists."
  fi
}

# Function to create ECS cluster if it doesn't exist
create_ecs_cluster() {
  echo "Creating ECS Cluster..."
  if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --query "clusters[?clusterName=='$CLUSTER_NAME']" | grep -q "$CLUSTER_NAME"; then
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo "ECS Cluster '$CLUSTER_NAME' created."
  else
    echo "ECS Cluster '$CLUSTER_NAME' already exists."
  fi
}

# Function to retrieve Default VPC and Subnets
retrieve_default_vpc_and_subnets() {
  echo "Retrieving Default VPC and Subnets..."

  # Get Default VPC ID
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

  # Get Default Subnets IDs
  DEFAULT_SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=default-for-az,Values=true" \
    --query "Subnets[].SubnetId" \
    --output text \
    --region "$AWS_REGION")

  if [ -z "$DEFAULT_SUBNET_IDS" ] || [ "$DEFAULT_SUBNET_IDS" == "None" ]; then
    echo "Error: No default subnets found in VPC '$DEFAULT_VPC_ID'. Please ensure default subnets exist."
    exit 1
  fi

  echo "Default Subnet IDs: $DEFAULT_SUBNET_IDS"

  # Assign to SUBNETS variable as a comma-separated list
  SUBNETS=$(echo "$DEFAULT_SUBNET_IDS" | tr '\n' ',' | sed 's/,$//')
}

# Function to create Security Group if it doesn't exist
create_security_group() {
  echo "Creating security group..."
  SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SECURITY_GROUP_NAME" Name=vpc-id,Values="$DEFAULT_VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text --region "$AWS_REGION")

  if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
      --group-name "$SECURITY_GROUP_NAME" \
      --description "$DESCRIPTION" \
      --vpc-id "$DEFAULT_VPC_ID" \
      --query 'GroupId' \
      --output text --region "$AWS_REGION")
    echo "Security Group '$SECURITY_GROUP_NAME' created with ID: $SECURITY_GROUP_ID"
  else
    echo "Security Group '$SECURITY_GROUP_NAME' already exists with ID: $SECURITY_GROUP_ID"
  fi

  # Allow inbound traffic on CONTAINER_PORT from anywhere if not already allowed
  INGRESS_RULE_EXISTS=$(aws ec2 describe-security-groups \
    --group-id "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`'"$CONTAINER_PORT"'` && FromPort==`'"$CONTAINER_PORT"'` && IpProtocol==`tcp` && contains(IpRanges[].CidrIp, `0.0.0.0/0`)]' \
    --output text --region "$AWS_REGION")

  if [ -z "$INGRESS_RULE_EXISTS" ]; then
    aws ec2 authorize-security-group-ingress \
      --group-id "$SECURITY_GROUP_ID" \
      --protocol tcp \
      --port "$CONTAINER_PORT" \
      --cidr 0.0.0.0/0 \
      --region "$AWS_REGION"
    echo "Inbound rule added to allow TCP traffic on port $CONTAINER_PORT from 0.0.0.0/0."
  else
    echo "Inbound rule for port $CONTAINER_PORT already exists."
  fi
}

# Function to create CloudWatch Logs group if it doesn't exist
create_log_group() {
  echo "Creating CloudWatch Logs group..."
  LOG_GROUP_NAME="/ecs/$TASK_FAMILY"
  if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --region "$AWS_REGION" | grep -q "$LOG_GROUP_NAME"; then
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION"
    echo "Log group '$LOG_GROUP_NAME' created."
  else
    echo "Log group '$LOG_GROUP_NAME' already exists."
  fi
}

# Function to register ECS task definition
register_task_definition() {
  echo "Registering task definition..."

  # Ensure the log group exists
  create_log_group

  TASK_DEFINITION=$(aws ecs register-task-definition \
    --family "$TASK_FAMILY" \
    --execution-role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME" \
    --network-mode awsvpc \
    --container-definitions "[
      {
        \"name\": \"$CONTAINER_NAME\",
        \"image\": \"$IMAGE_NAME\",
        \"memory\": $MEMORY,
        \"cpu\": $CPU,
        \"essential\": true,
        \"portMappings\": [
          {
            \"containerPort\": $CONTAINER_PORT,
            \"hostPort\": $CONTAINER_PORT,
            \"protocol\": \"tcp\"
          }
        ],
        \"logConfiguration\": {
          \"logDriver\": \"awslogs\",
          \"options\": {
            \"awslogs-group\": \"$LOG_GROUP_NAME\",
            \"awslogs-region\": \"$AWS_REGION\",
            \"awslogs-stream-prefix\": \"ecs\"
          }
        }
      }
    ]" \
    --requires-compatibilities FARGATE \
    --cpu "$CPU" \
    --memory "$MEMORY" \
    --region "$AWS_REGION" \
    --output json)

  TASK_REVISION=$(echo "$TASK_DEFINITION" | jq -r '.taskDefinition.revision')
  echo "Task definition registered as revision $TASK_REVISION."
}

# Function to create or update ECS service
create_or_update_ecs_service() {
  echo "Creating or updating ECS service..."
  SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text)

  if [ "$SERVICE_EXISTS" != "None" ] && [ -n "$SERVICE_EXISTS" ]; then
    echo "ECS Service '$SERVICE_NAME' already exists. Updating service..."
    aws ecs update-service \
      --cluster "$CLUSTER_NAME" \
      --service "$SERVICE_NAME" \
      --task-definition "${TASK_FAMILY}:${TASK_REVISION}" \
      --desired-count "$DESIRED_COUNT" \
      --region "$AWS_REGION"
    echo "ECS Service '$SERVICE_NAME' updated."
  else
    echo "Creating ECS Service '$SERVICE_NAME'..."
    aws ecs create-service \
      --cluster "$CLUSTER_NAME" \
      --service-name "$SERVICE_NAME" \
      --task-definition "${TASK_FAMILY}:${TASK_REVISION}" \
      --desired-count "$DESIRED_COUNT" \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
      --region "$AWS_REGION"
    echo "ECS Service '$SERVICE_NAME' created."
  fi
}

# ---------------------------
# Main Script Execution
# ---------------------------

# Initialize default values
AWS_REGION="us-east-2"
DESIRED_COUNT=1

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --region)
      if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
        AWS_REGION="$2"
        shift
      else
        echo "Error: --region requires a non-empty argument."
        usage
      fi
      ;;
    --desired-count)
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        DESIRED_COUNT="$2"
        shift
      else
        echo "Error: --desired-count requires a numeric argument."
        usage
      fi
      ;;
    *)
      echo "Unknown parameter passed: $1"
      usage
      ;;
  esac
  shift
done

echo "Deployment initiated with the following parameters:"
echo "  AWS Region       : $AWS_REGION"
echo "  Desired Count    : $DESIRED_COUNT"

# Check for required commands
for cmd in aws docker jq; do
  check_command "$cmd"
done

# Configure AWS CLI if necessary
configure_aws_cli

# Retrieve AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --region "$AWS_REGION")
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Define variables
REPO_NAME="patient-survival-prediction-repo"
CLUSTER_NAME="patient-survival-cluster"
TASK_FAMILY="patient-survival-task-family"
CONTAINER_NAME="patient-survival-container"
IMAGE_NAME="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest"
ROLE_NAME="ecsTaskExecutionRole"
SERVICE_NAME="patient-survival-service"
CONTAINER_PORT=80  # Change if your application uses a different port
MEMORY="3072"  # 3 GB in MiB
CPU="1024"     # 1 vCPU
SECURITY_GROUP_NAME="ecs-security-group"
DESCRIPTION="Security group for ECS service"
LOG_GROUP_NAME="/ecs/$TASK_FAMILY"

# Execute deployment steps
create_ecr_repository
build_and_push_docker_image
create_iam_role
create_ecs_cluster
retrieve_default_vpc_and_subnets
create_security_group
register_task_definition
create_or_update_ecs_service

echo "Deployment complete. Your Patient Survival Prediction application should now be running in ECS."