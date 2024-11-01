Patient Survival Prediction Application Deployment

This document guides you through deploying a Gradio-based Patient Survival Prediction application on AWS ECS with Docker, ECR, IAM, and ECS configuration, along with a rollback script to clean up resources.

Table of Contents

	•	Prerequisites
	•	Deployment Steps
	•	Step 0: Configure AWS CLI
	•	Step 1: Create ECR Repository
	•	Step 2: Build Docker Image and Push to ECR
	•	Step 3: Create IAM Role for ECS Task Execution
	•	Step 4: Create ECS Cluster
	•	Step 5: Register ECS Task Definition
	•	Step 6: Create ECS Service
	•	Rollback Process

Prerequisites

	1.	AWS Account: Ensure you have an AWS account with permissions to create and manage ECR, IAM, and ECS resources.
	2.	AWS CLI: Install and configure the AWS CLI.
	•	AWS CLI Installation Guide
	3.	Docker: Install Docker and ensure the Docker daemon is running on your local machine.
	•	Docker Installation Guide

Deployment Steps

Follow these steps to deploy the application on AWS ECS.

Step 0: Configure AWS CLI

To configure the AWS CLI, use the command below and follow the prompts:

aws configure

Provide the following information when prompted:

	•	Access Key ID
	•	Secret Access Key
	•	Region (e.g., us-west-2)
	•	Output format: json

Step 1: Create ECR Repository

Create an ECR repository to store the Docker image for the Patient Survival Prediction application.

AWS_REGION="your-aws-region"  # Replace with your AWS region
REPO_NAME="patient-survival-prediction-repo"

aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

Step 2: Build Docker Image and Push to ECR

	1.	Build the Docker Image:

docker build -t $REPO_NAME .


	2.	Log in to ECR:

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com


	3.	Tag and Push the Docker Image:

IMAGE_NAME="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest"
docker tag $REPO_NAME:latest $IMAGE_NAME
docker push $IMAGE_NAME



Step 3: Create IAM Role for ECS Task Execution

	1.	Create the IAM Role:

ROLE_NAME="ecsTaskExecutionRole"

aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}' --region $AWS_REGION


	2.	Attach Necessary Policies:

aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy



Step 4: Create ECS Cluster

CLUSTER_NAME="patient-survival-cluster"

aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION

Step 5: Register ECS Task Definition

	1.	Define Task Family and Parameters:

TASK_FAMILY="patient-survival-task-family"
CONTAINER_NAME="patient-survival-container"
CONTAINER_PORT=8001  # Update if using a different port
MEMORY="3000"  # 3GB in MB
CPU="1024"     # 1 vCPU


	2.	Register Task Definition:

aws ecs register-task-definition \
  --family $TASK_FAMILY \
  --execution-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME \
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
      ]
    }
  ]" \
  --requires-compatibilities FARGATE \
  --cpu $CPU \
  --memory $MEMORY \
  --region $AWS_REGION



Step 6: Create ECS Service

SERVICE_NAME="patient-survival-service"

aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-your-subnet-id],securityGroups=[sg-your-security-group-id],assignPublicIp=ENABLED}" \
  --region $AWS_REGION

After this step, your Patient Survival Prediction application should be running in ECS.

Rollback Process

If you need to roll back or remove the resources created by the deployment, follow these steps:

	1.	Delete ECS Service:

aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count 0 --region $AWS_REGION
aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --force --region $AWS_REGION


	2.	Deregister ECS Task Definitions:

TASK_DEFINITION_ARN=$(aws ecs list-task-definitions --family-prefix $TASK_FAMILY --region $AWS_REGION --query "taskDefinitionArns[-1]" --output text)
if [ "$TASK_DEFINITION_ARN" != "None" ]; then
    aws ecs deregister-task-definition --task-definition $TASK_DEFINITION_ARN --region $AWS_REGION
fi


	3.	Delete ECS Cluster:

aws ecs delete-cluster --cluster $CLUSTER_NAME --region $AWS_REGION


	4.	Delete IAM Role and Policies:

aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name $ROLE_NAME


	5.	Delete ECR Repository:

aws ecr delete-repository --repository-name $REPO_NAME --force --region $AWS_REGION
