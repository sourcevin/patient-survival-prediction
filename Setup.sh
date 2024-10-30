#!/bin/bash

# Variables
AWS_REGION="your-aws-region"  # e.g., us-west-2
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REPO_NAME="patient-survival-prediction-repo"
CLUSTER_NAME="patient-survival-cluster"
TASK_FAMILY="patient-survival-task-family"
CONTAINER_NAME="patient-survival-container"
IMAGE_NAME="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest"
ROLE_NAME="ecsTaskExecutionRole"
SERVICE_NAME="patient-survival-service"
CONTAINER_PORT=8001  # Change this if your application uses a different port
MEMORY="3GB"
CPU="1vCPU"

# Step 1: Create ECR Repository
echo "Creating ECR repository..."
aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

# Step 2: Build Docker Image and Push to ECR
echo "Building Docker image..."
docker build -t $REPO_NAME .

echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "Tagging Docker image..."
docker tag $REPO_NAME:latest $IMAGE_NAME

echo "Pushing Docker image to ECR..."
docker push $IMAGE_NAME

# Step 3: Create IAM Role for ECS Task Execution
echo "Creating IAM role for ECS task execution..."
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

aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Step 4: Create ECS Cluster
echo "Creating ECS Cluster..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION

# Step 5: Register Task Definition
echo "Registering task definition..."
aws ecs register-task-definition \
  --family $TASK_FAMILY \
  --execution-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME \
  --network-mode awsvpc \
  --container-definitions "[
    {
      \"name\": \"$CONTAINER_NAME\",
      \"image\": \"$IMAGE_NAME\",
      \"memory\": 3000,
      \"cpu\": 1024,
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

# Step 6: Create ECS Service
echo "Creating ECS service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-your-subnet-id],securityGroups=[sg-your-security-group-id],assignPublicIp=ENABLED}" \
  --region $AWS_REGION

echo "Deployment complete. Your Patient Survival Prediction application should now be running in ECS."