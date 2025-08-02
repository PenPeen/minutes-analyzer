# Environment Configuration (with fallbacks)
AWS_REGION ?= ap-northeast-1
LOCALSTACK_ENDPOINT ?= http://localhost:4566
PROJECT_NAME ?= minutes-analyzer
ENVIRONMENT ?= local

# Path Configuration (absolute paths)
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TF_DIR := $(MAKEFILE_DIR)../infrastructure/environments/local
LAMBDA_DIR := $(MAKEFILE_DIR)../lambda
DOCKER_COMPOSE_FILE := $(MAKEFILE_DIR)../docker-compose.yml

# Build Configuration
LAMBDA_ZIP := infrastructure/modules/lambda/lambda.zip
BUNDLE_TIMESTAMP := $(LAMBDA_DIR)/vendor/bundle/.timestamp

# LocalStack Configuration
LOCALSTACK_TIMEOUT ?= 60
LOCALSTACK_CHECK_INTERVAL ?= 2
LOCALSTACK_MAX_RETRIES ?= 30
LOCALSTACK_VOLUME_DIR ?= ./infrastructure/infrastructure/volume

# Validation
ifndef PROJECT_NAME
    $(error PROJECT_NAME must be defined)
endif
