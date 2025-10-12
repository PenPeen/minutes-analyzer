import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

interface DriveSelectorStackProps extends cdk.StackProps {
  analyzerFunctionArn: string;
}

export class DriveSelectorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: DriveSelectorStackProps) {
    super(scope, id, props);

    new lambda.Function(this, 'SlackBotFunction', {
      functionName: 'drive-selector-production',
      runtime: lambda.Runtime.RUBY_3_2,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset('../drive-selector/infrastructure/modules/lambda/lambda.zip'),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256
    });
  }
}
