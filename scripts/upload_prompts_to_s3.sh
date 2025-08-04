#!/bin/bash

# Upload prompts to S3 bucket
# Usage: ./upload_prompts_to_s3.sh [environment]

set -e

# Configuration
ENVIRONMENT=${1:-local}
PROJECT_NAME="minutes-analyzer"
PROMPTS_DIR="./prompts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting prompt upload to S3...${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"

# Set AWS endpoint for LocalStack if local environment
if [ "$ENVIRONMENT" = "local" ]; then
  AWS_ENDPOINT="--endpoint-url=http://localhost:4566"
  export AWS_ACCESS_KEY_ID=test
  export AWS_SECRET_ACCESS_KEY=test
  export AWS_REGION=ap-northeast-1
  # Disable AWS CLI v2 features that may cause issues with LocalStack
  export AWS_CLI_V2_DATALOADER=0
  export AWS_DISABLE_REQUEST_COMPRESSION=true
else
  AWS_ENDPOINT=""
fi

# Bucket name
BUCKET_NAME="${PROJECT_NAME}-prompts-${ENVIRONMENT}"

echo -e "${GREEN}Uploading prompts to bucket: ${BUCKET_NAME}${NC}"

# Check if bucket exists
if ! aws s3 ls "s3://${BUCKET_NAME}" ${AWS_ENDPOINT} >/dev/null 2>&1; then
  echo -e "${RED}Error: Bucket ${BUCKET_NAME} does not exist${NC}"
  echo "Please run 'terraform apply' first to create the bucket"
  exit 1
fi

# Upload prompt files
# HACK: AWS CLI v2 (2.28+) sends x-amz-trailer header which LocalStack doesn't support
# This causes "The value specified in the x-amz-trailer header is not supported" error
# As a workaround, we use curl for direct HTTP PUT to LocalStack's S3 endpoint
# Issue tracking: https://github.com/localstack/localstack/issues/9023
# TODO: Remove this workaround when LocalStack supports x-amz-trailer header
if [ "$ENVIRONMENT" = "local" ]; then
  echo -e "${YELLOW}Uploading meeting_analysis_prompt.txt (using LocalStack workaround)...${NC}"
  curl -s -X PUT \
    -T "${PROMPTS_DIR}/meeting_analysis_prompt.txt" \
    "http://localhost:4566/${BUCKET_NAME}/prompts/meeting_analysis_prompt.txt"
  
  echo -e "${YELLOW}Uploading output_schema.json (using LocalStack workaround)...${NC}"
  curl -s -X PUT \
    -T "${PROMPTS_DIR}/output_schema.json" \
    "http://localhost:4566/${BUCKET_NAME}/schemas/output_schema.json"
else
  # For real AWS, use standard s3api
  echo -e "${YELLOW}Uploading meeting_analysis_prompt.txt...${NC}"
  aws s3api put-object \
    --bucket "${BUCKET_NAME}" \
    --key "prompts/meeting_analysis_prompt.txt" \
    --body "${PROMPTS_DIR}/meeting_analysis_prompt.txt" >/dev/null
  
  echo -e "${YELLOW}Uploading output_schema.json...${NC}"
  aws s3api put-object \
    --bucket "${BUCKET_NAME}" \
    --key "schemas/output_schema.json" \
    --body "${PROMPTS_DIR}/output_schema.json" >/dev/null
fi

# List uploaded files
echo -e "${GREEN}Files uploaded successfully!${NC}"
echo -e "${YELLOW}Current bucket contents:${NC}"
aws s3 ls "s3://${BUCKET_NAME}/" --recursive ${AWS_ENDPOINT}

echo -e "${GREEN}✅ Prompt upload completed!${NC}"