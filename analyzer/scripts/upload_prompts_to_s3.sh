#!/bin/bash

# Upload prompts to S3 bucket
# Usage: ./upload_prompts_to_s3.sh [environment]

set -e

# Configuration
ENVIRONMENT=${1:-production}
PROJECT_NAME="minutes-analyzer"
PROMPTS_DIR="./prompts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting prompt upload to S3...${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"

AWS_ENDPOINT=""

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
echo -e "${YELLOW}Uploading meeting_analysis_prompt.txt...${NC}"
aws s3api put-object \
  --bucket "${BUCKET_NAME}" \
  --key "prompts/meeting_analysis_prompt.txt" \
  --body "${PROMPTS_DIR}/meeting_analysis_prompt.txt" >/dev/null

echo -e "${YELLOW}Uploading meeting_verification_prompt.txt...${NC}"
aws s3api put-object \
  --bucket "${BUCKET_NAME}" \
  --key "prompts/meeting_verification_prompt.txt" \
  --body "${PROMPTS_DIR}/meeting_verification_prompt.txt" >/dev/null

echo -e "${YELLOW}Uploading output_schema.json...${NC}"
aws s3api put-object \
  --bucket "${BUCKET_NAME}" \
  --key "schemas/output_schema.json" \
  --body "${PROMPTS_DIR}/output_schema.json" >/dev/null

# List uploaded files
echo -e "${GREEN}Files uploaded successfully!${NC}"
echo -e "${YELLOW}Current bucket contents:${NC}"
aws s3 ls "s3://${BUCKET_NAME}/" --recursive

echo -e "${GREEN}✅ Prompt upload completed!${NC}"