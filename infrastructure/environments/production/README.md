# Production Environment

This directory contains Terraform configuration for deploying the Minutes Analyzer to production AWS.

## Setup

1. Copy the sample configuration files:
```bash
# Copy non-sensitive configuration
cp terraform.tfvars.sample terraform.tfvars

# Copy sensitive configuration
cp .env.tfvars.sample .env.tfvars
```

2. Edit `terraform.tfvars` with your production configuration:
- Adjust Lambda memory and timeout if needed
- Configure feature flags
- Set other non-sensitive values

3. Edit `.env.tfvars` with your sensitive values:
- Add your Slack webhook URL
- Add any other sensitive configuration

4. Set up AWS credentials:
```bash
export AWS_PROFILE=your-production-profile
# or
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
```

5. Initialize and deploy:
```bash
make deploy-production
```

## Important Notes

- The Gemini API key should be set manually in AWS Secrets Manager after deployment
- S3 backend for Terraform state is configured but the bucket needs to be created separately
- CloudWatch alarms are configured for monitoring Lambda errors and throttles

## Differences from Local Environment

- No LocalStack endpoints configuration
- S3 backend for state management
- Production-grade monitoring with CloudWatch alarms
- Higher Lambda memory (512MB) and timeout (15 minutes)
- API key required for API Gateway