# Terraform → AWS CDK 移行計画

## 📊 現状調査結果

### 1. プロジェクト構成
本プロジェクトは2つの独立したマイクロサービスで構成されています：

#### **analyzer（議事録分析エンジン）**
- **Lambda関数**: Ruby 3.3、タイムアウト900秒、メモリ1024MB
- **S3バケット**: プロンプトファイル保存用（KMS暗号化）
- **Secrets Manager**: API Key等の機密情報管理
- **KMS Key**: 暗号化用（キーローテーション有効）
- **CloudWatch Logs**: ログ保存（30日保持、KMS暗号化）
- **CloudWatch Alarms**: エラー・スロットル監視
- **IAM Role/Policy**: Lambda実行ロール、S3/Secrets Manager/KMSアクセス権限

#### **drive-selector（Slack Bot）**
- **Lambda関数**: Ruby 3.2、タイムアウト30秒、メモリ256MB
- **API Gateway**: REST API（4エンドポイント: commands, interactions, oauth/callback, health）
- **DynamoDB**: OAuth トークン保存（TTL有効、暗号化）
- **Secrets Manager**: Slack/Google認証情報管理
- **CloudWatch Logs**: ログ保存（30日保持）
- **IAM Role/Policy**: Lambda実行ロール、DynamoDB/Secrets Manager/Lambda Invokeアクセス権限
- **API Gateway Usage Plan**: レート制限（5req/s、100req/day）

### 2. サービス間連携
- drive-selector → analyzer へのLambda Invoke権限
- analyzer ← drive-selector からのInvoke許可

### 3. Terraform管理範囲
- **Backend**: S3（暗号化、バージョニング無効）
- **State管理**: 各サービス独立したStateファイル
- **デプロイフロー**: Makefile経由でビルド→Terraform Apply

---

## 🎯 移行計画概要

### 目的
TerraformからAWS CDKへ移行し、TypeScript/Pythonによる型安全なIaC管理を実現

### 成功基準
- 既存のAWSリソースをCDKで完全再現
- デプロイフローの簡素化
- 既存のMakefileコマンドとの互換性維持

### スコープ
- analyzer、drive-selectorの両サービスをCDKで実装
- CDK Stackの分離（analyzer-stack、drive-selector-stack）
- 既存のLambdaビルドプロセスは維持

### 非スコープ
- Lambda関数のRubyコード変更
- 環境変数管理方法の変更（.env.production継続使用）
- CI/CDパイプライン構築

---

## 📋 タスク一覧

### T-01: CDKプロジェクト初期化
- **概要**: CDKプロジェクトのセットアップとディレクトリ構造作成
- **理由**: CDK移行の基盤となるプロジェクト構造が必要
- **受け入れ条件**: 
  - `cdk/` ディレクトリ配下にCDKプロジェクトが作成される
  - `cdk init app --language typescript` が実行される
  - package.jsonに必要な依存関係が追加される
- **依存関係**: なし
- **ブランチ**: `feature/cdk-migration-init`

#### 実装内容

**ファイル構成**:
```
minutes-analyzer/
├── cdk/
│   ├── bin/
│   │   └── app.ts
│   ├── lib/
│   │   ├── analyzer-stack.ts
│   │   └── drive-selector-stack.ts
│   ├── cdk.json
│   ├── package.json
│   └── tsconfig.json
```

**cdk/package.json**:
```json
{
  "name": "minutes-analyzer-cdk",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "cdk": "cdk",
    "deploy:analyzer": "cdk deploy AnalyzerStack",
    "deploy:drive-selector": "cdk deploy DriveSelectorStack",
    "deploy:all": "cdk deploy --all",
    "destroy:analyzer": "cdk destroy AnalyzerStack",
    "destroy:drive-selector": "cdk destroy DriveSelectorStack"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "aws-cdk": "^2.120.0",
    "typescript": "^5.3.0"
  },
  "dependencies": {
    "aws-cdk-lib": "^2.120.0",
    "constructs": "^10.3.0",
    "dotenv": "^16.3.1"
  }
}
```

**cdk/bin/app.ts**:
```typescript
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AnalyzerStack } from '../lib/analyzer-stack';
import { DriveSelectorStack } from '../lib/drive-selector-stack';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../../analyzer/.env.production') });
dotenv.config({ path: path.join(__dirname, '../../drive-selector/.env.production') });

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: 'ap-northeast-1'
};

const analyzerStack = new AnalyzerStack(app, 'AnalyzerStack', {
  env,
  stackName: 'minutes-analyzer-production',
  description: 'Minutes Analyzer Lambda Function Stack'
});

const driveSelectorStack = new DriveSelectorStack(app, 'DriveSelectorStack', {
  env,
  stackName: 'drive-selector-production',
  description: 'Drive Selector Slack Bot Stack',
  analyzerFunctionArn: analyzerStack.lambdaFunction.functionArn
});

// Add dependency
driveSelectorStack.addDependency(analyzerStack);
```

**cdk/cdk.json**:
```json
{
  "app": "npx ts-node --prefer-ts-exts bin/app.ts",
  "watch": {
    "include": ["**"],
    "exclude": [
      "README.md",
      "cdk*.json",
      "**/*.d.ts",
      "**/*.js",
      "tsconfig.json",
      "package*.json",
      "yarn.lock",
      "node_modules"
    ]
  },
  "context": {
    "@aws-cdk/aws-lambda:recognizeLayerVersion": true,
    "@aws-cdk/core:checkSecretUsage": true,
    "@aws-cdk/core:target-partitions": ["aws", "aws-cn"]
  }
}
```

**cdk/tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["es2020"],
    "declaration": true,
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noImplicitThis": true,
    "alwaysStrict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": false,
    "inlineSourceMap": true,
    "inlineSources": true,
    "experimentalDecorators": true,
    "strictPropertyInitialization": false,
    "typeRoots": ["./node_modules/@types"],
    "esModuleInterop": true,
    "resolveJsonModule": true
  },
  "exclude": ["node_modules", "cdk.out"]
}
```

---

### T-02: Analyzer Stack実装
- **概要**: analyzer用のCDK Stackを実装
- **理由**: 議事録分析エンジンのインフラをCDKで管理
- **受け入れ条件**:
  - Lambda、S3、KMS、Secrets Manager、CloudWatch、IAMがCDKで定義される
  - 既存Terraformと同等のリソースが作成される
- **依存関係**: T-01
- **ブランチ**: `feature/cdk-analyzer-stack`

#### 実装内容

**cdk/lib/analyzer-stack.ts**:
```typescript
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';
import * as path from 'path';

export class AnalyzerStack extends cdk.Stack {
  public readonly lambdaFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const projectName = 'minutes-analyzer';
    const environment = 'production';

    // KMS Key
    const kmsKey = new kms.Key(this, 'KmsKey', {
      description: `KMS key for ${projectName}-${environment} encryption`,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    new kms.Alias(this, 'KmsAlias', {
      aliasName: `alias/${projectName}-${environment}`,
      targetKey: kmsKey
    });

    // Secrets Manager
    const appSecrets = new secretsmanager.Secret(this, 'AppSecrets', {
      secretName: `${projectName}-secrets-${environment}`,
      encryptionKey: kmsKey,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // S3 Bucket for prompts
    const promptsBucket = new s3.Bucket(this, 'PromptsBucket', {
      bucketName: `${projectName}-prompts-${environment}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: kmsKey,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // CloudWatch Log Group
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-${environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      encryptionKey: kmsKey,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Lambda Execution Role
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role-${environment}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Grant permissions
    appSecrets.grantRead(lambdaRole);
    promptsBucket.grantRead(lambdaRole);
    kmsKey.grantEncryptDecrypt(lambdaRole);

    // Lambda Function
    this.lambdaFunction = new lambda.Function(this, 'AnalyzerFunction', {
      functionName: `${projectName}-${environment}`,
      runtime: lambda.Runtime.RUBY_3_3,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../analyzer/infrastructure/modules/lambda/lambda.zip')),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(900),
      memorySize: 1024,
      environment: {
        ENVIRONMENT: environment,
        APP_SECRETS_NAME: appSecrets.secretName,
        PROMPTS_BUCKET_NAME: promptsBucket.bucketName,
        LOG_LEVEL: process.env.LOG_LEVEL || 'INFO',
        AI_MODEL: process.env.AI_MODEL || 'gemini-2.5-flash',
        GOOGLE_CALENDAR_ENABLED: process.env.GOOGLE_CALENDAR_ENABLED || 'true',
        USER_MAPPING_ENABLED: process.env.USER_MAPPING_ENABLED || 'true',
        CACHE_TTL: process.env.CACHE_TTL || '600',
        SLACK_CHANNEL_ID: process.env.SLACK_CHANNEL_ID || ''
      },
      logGroup: logGroup
    });

    // CloudWatch Alarms
    new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `${projectName}-lambda-errors-${environment}`,
      metric: this.lambdaFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    new cloudwatch.Alarm(this, 'LambdaThrottlesAlarm', {
      alarmName: `${projectName}-lambda-throttles-${environment}`,
      metric: this.lambdaFunction.metricThrottles({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 10,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Outputs
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Name of the Lambda function'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'ARN of the Lambda function'
    });

    new cdk.CfnOutput(this, 'SecretName', {
      value: appSecrets.secretName,
      description: 'Secret name for application secrets'
    });
  }
}
```

---

### T-03: Drive Selector Stack実装
- **概要**: drive-selector用のCDK Stackを実装
- **理由**: Slack BotのインフラをCDKで管理
- **受け入れ条件**:
  - Lambda、API Gateway、DynamoDB、Secrets Manager、IAMがCDKで定義される
  - analyzer Lambdaへの呼び出し権限が設定される
- **依存関係**: T-02
- **ブランチ**: `feature/cdk-drive-selector-stack`

#### 実装内容

**cdk/lib/drive-selector-stack.ts**:
```typescript
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as path from 'path';

interface DriveSelectorStackProps extends cdk.StackProps {
  analyzerFunctionArn: string;
}

export class DriveSelectorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: DriveSelectorStackProps) {
    super(scope, id, props);

    const projectName = 'drive-selector';
    const environment = 'production';

    // Secrets Manager
    const appSecrets = new secretsmanager.Secret(this, 'AppSecrets', {
      secretName: `${projectName}-secrets-${environment}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // DynamoDB Table for OAuth tokens
    const oauthTokensTable = new dynamodb.Table(this, 'OAuthTokensTable', {
      tableName: `${projectName}-oauth-tokens-${environment}`,
      partitionKey: { name: 'user_id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      timeToLiveAttribute: 'expires_at',
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // CloudWatch Log Group
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-${environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Lambda Execution Role
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role-${environment}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Grant permissions
    appSecrets.grantRead(lambdaRole);
    oauthTokensTable.grantReadWriteData(lambdaRole);

    // Grant Lambda Invoke permission to analyzer
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['lambda:InvokeFunction'],
      resources: [props.analyzerFunctionArn]
    }));

    // Lambda Function
    const slackBotFunction = new lambda.Function(this, 'SlackBotFunction', {
      functionName: `${projectName}-${environment}`,
      runtime: lambda.Runtime.RUBY_3_2,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../drive-selector/infrastructure/modules/lambda/lambda.zip')),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        ENVIRONMENT: environment,
        APP_SECRETS_NAME: appSecrets.secretName,
        SECRETS_MANAGER_SECRET_ID: appSecrets.secretName,
        LOG_LEVEL: 'INFO',
        SLACK_CHANNEL_ID: process.env.SLACK_CHANNEL_ID || '',
        OAUTH_TOKENS_TABLE_NAME: oauthTokensTable.tableName
      },
      logGroup: logGroup
    });

    // API Gateway
    const api = new apigateway.RestApi(this, 'SlackBotApi', {
      restApiName: `${projectName}-api-${environment}`,
      description: 'API Gateway for Slack Bot Drive Selector',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL]
      },
      deployOptions: {
        stageName: environment,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true
      }
    });

    // API Resources
    const slack = api.root.addResource('slack');
    const commands = slack.addResource('commands');
    const interactions = slack.addResource('interactions');
    const oauth = api.root.addResource('oauth');
    const oauthCallback = oauth.addResource('callback');
    const health = api.root.addResource('health');

    // Lambda Integration
    const lambdaIntegration = new apigateway.LambdaIntegration(slackBotFunction, {
      proxy: true
    });

    // API Methods
    commands.addMethod('POST', lambdaIntegration);
    interactions.addMethod('POST', lambdaIntegration);
    oauthCallback.addMethod('GET', lambdaIntegration);
    health.addMethod('GET', lambdaIntegration);

    // API Key and Usage Plan
    const apiKey = api.addApiKey('ApiKey', {
      apiKeyName: `${projectName}-api-key-${environment}`
    });

    const usagePlan = api.addUsagePlan('UsagePlan', {
      name: `${projectName}-usage-plan-${environment}`,
      description: 'Usage plan for Slack Bot API with rate limiting',
      throttle: {
        rateLimit: 5,
        burstLimit: 10
      },
      quota: {
        limit: 100,
        period: apigateway.Period.DAY
      }
    });

    usagePlan.addApiKey(apiKey);
    usagePlan.addApiStage({
      stage: api.deploymentStage
    });

    // Grant analyzer Lambda permission to be invoked by drive-selector
    const analyzerFunction = lambda.Function.fromFunctionArn(
      this,
      'AnalyzerFunction',
      props.analyzerFunctionArn
    );

    analyzerFunction.grantInvoke(lambdaRole);

    // Outputs
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: slackBotFunction.functionName,
      description: 'Name of the Lambda function'
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway URL'
    });

    new cdk.CfnOutput(this, 'ApiGatewayCommandsUrl', {
      value: `${api.url}slack/commands`,
      description: 'API Gateway URL for Slack commands'
    });

    new cdk.CfnOutput(this, 'ApiGatewayInteractionsUrl', {
      value: `${api.url}slack/interactions`,
      description: 'API Gateway URL for Slack interactions'
    });

    new cdk.CfnOutput(this, 'ApiKeyId', {
      value: apiKey.keyId,
      description: 'API Gateway API Key ID'
    });
  }
}
```

---

### T-04: Makefile統合とデプロイスクリプト
- **概要**: 既存MakefileにCDKコマンドを統合
- **理由**: 既存のデプロイフローとの互換性維持
- **受け入れ条件**:
  - `make deploy-production-cdk` でCDKデプロイが実行される
  - `make destroy-production-cdk` でCDK破棄が実行される
  - 既存のTerraformコマンドと共存できる
- **依存関係**: T-03
- **ブランチ**: `feature/cdk-makefile-integration`

#### 実装内容

**analyzer/Makefile（追加部分）**:
```makefile
# CDK関連コマンド
cdk-setup: ## CDKプロジェクトのセットアップ
	@echo "📦 CDKプロジェクトをセットアップ中..."
	@cd ../cdk && npm install
	@echo "✅ CDKセットアップが完了しました"

cdk-build: build-lambda ## CDK用にLambda関数をビルド
	@echo "🔨 CDK用Lambda関数をビルド中..."
	@$(MAKE) build-lambda
	@echo "✅ CDK用ビルドが完了しました"

cdk-synth: cdk-build ## CDK CloudFormationテンプレートを生成
	@echo "📋 CDK CloudFormationテンプレートを生成中..."
	@cd ../cdk && npm run build && npx cdk synth AnalyzerStack
	@echo "✅ CDK synthが完了しました"

cdk-deploy-production: cdk-build ## CDKで本番環境にデプロイ
	@echo "🚀 CDKで本番環境にデプロイ中..."
	@if [ ! -f .env.production ]; then \
		echo "❌ .env.productionが見つかりません。"; \
		exit 1; \
	fi
	@cd ../cdk && npm run build && npx cdk deploy AnalyzerStack --require-approval never
	@echo "🔐 Secrets Managerにシークレットを設定中..."
	@./scripts/set-production-secrets.sh
	@$(MAKE) upload-prompts-production
	@echo "✅ CDKデプロイが完了しました"

cdk-destroy-production: ## CDKで本番環境を削除
	@echo "🗑️  CDKで本番環境を削除中..."
	@cd ../cdk && npx cdk destroy AnalyzerStack --force
	@echo "✅ CDK削除が完了しました"

cdk-diff: ## CDKの差分を表示
	@echo "🔍 CDKの差分を表示中..."
	@cd ../cdk && npm run build && npx cdk diff AnalyzerStack
```

**drive-selector/Makefile（追加部分）**:
```makefile
# CDK関連コマンド
cdk-setup: ## CDKプロジェクトのセットアップ
	@echo "📦 CDKプロジェクトをセットアップ中..."
	@cd ../cdk && npm install
	@echo "✅ CDKセットアップが完了しました"

cdk-build: build-production ## CDK用にLambda関数をビルド
	@echo "🔨 CDK用Lambda関数をビルド中..."
	@$(MAKE) build-production
	@echo "✅ CDK用ビルドが完了しました"

cdk-synth: cdk-build ## CDK CloudFormationテンプレートを生成
	@echo "📋 CDK CloudFormationテンプレートを生成中..."
	@cd ../cdk && npm run build && npx cdk synth DriveSelectorStack
	@echo "✅ CDK synthが完了しました"

cdk-deploy-production: cdk-build ## CDKで本番環境にデプロイ
	@echo "🚀 CDKで本番環境にデプロイ中..."
	@if [ ! -f .env.production ]; then \
		echo "❌ .env.productionが見つかりません。"; \
		exit 1; \
	fi
	@cd ../cdk && npm run build && npx cdk deploy DriveSelectorStack --require-approval never
	@echo "🔐 Secrets Managerにシークレットを設定中..."
	@./scripts/set-production-secrets.sh
	@echo "✅ CDKデプロイが完了しました"

cdk-destroy-production: ## CDKで本番環境を削除
	@echo "🗑️  CDKで本番環境を削除中..."
	@cd ../cdk && npx cdk destroy DriveSelectorStack --force
	@echo "✅ CDK削除が完了しました"

cdk-diff: ## CDKの差分を表示
	@echo "🔍 CDKの差分を表示中..."
	@cd ../cdk && npm run build && npx cdk diff DriveSelectorStack
```

**cdk/scripts/deploy-all.sh**:
```bash
#!/bin/bash
set -e

echo "🚀 全サービスをCDKでデプロイ中..."

# Analyzer
echo "📦 Analyzerをデプロイ中..."
cd ../analyzer
make cdk-deploy-production

# Drive Selector
echo "📦 Drive Selectorをデプロイ中..."
cd ../drive-selector
make cdk-deploy-production

echo "✅ 全サービスのデプロイが完了しました"
```

---

### T-05: ドキュメント更新とマイグレーションガイド
- **概要**: README、ドキュメントをCDK対応に更新
- **理由**: ユーザーがCDKでデプロイできるようにする
- **受け入れ条件**:
  - README.mdにCDKデプロイ手順が追加される
  - Terraform→CDK移行ガイドが作成される
  - 既存のTerraform手順も残す（段階的移行のため）
- **依存関係**: T-04
- **ブランチ**: `feature/cdk-documentation`

#### 実装内容

**README.md（追加セクション）**:
```markdown
## 🚀 デプロイ方法

### CDKによるデプロイ（推奨）

#### 前提条件
```bash
# Node.js 18以上
node --version

# AWS CDK CLI
npm install -g aws-cdk
```

#### デプロイ手順
```bash
# 1. CDKプロジェクトのセットアップ
cd cdk
npm install

# 2. 環境変数設定
# analyzer/.env.production と drive-selector/.env.production を設定

# 3. Lambda関数ビルド
cd ../analyzer && make build-lambda
cd ../drive-selector && make build-production

# 4. CDKデプロイ
cd ../cdk
npm run deploy:all

# または個別デプロイ
npm run deploy:analyzer
npm run deploy:drive-selector
```

### Terraformによるデプロイ（従来方式）
従来通りのTerraformデプロイも引き続きサポートされています。
詳細は[Terraform デプロイガイド](docs/terraform-deployment.md)を参照してください。
```

**docs/cdk-migration-guide.md**:
```markdown
# Terraform → CDK 移行ガイド

## 移行手順

### 1. 既存Terraformリソースの削除
```bash
# analyzer
cd analyzer
make destroy-production

# drive-selector
cd drive-selector
make destroy-production
```

### 2. CDKプロジェクトのセットアップ
```bash
cd cdk
npm install
```

### 3. CDKでデプロイ
```bash
# analyzer
cd analyzer
make cdk-deploy-production

# drive-selector
cd drive-selector
make cdk-deploy-production
```

## 主な変更点

### メリット
- TypeScriptによる型安全なインフラ定義
- IDEの補完機能が使える
- リソース間の依存関係が明確
- デプロイ前の差分確認が容易

### 注意点
- Node.js環境が必要
- CDK CLIのインストールが必要
- 既存のTerraform stateは引き継がれない（再作成が必要）
```
