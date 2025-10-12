import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export class AnalyzerStack extends cdk.Stack {
  public readonly lambdaFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.lambdaFunction = new lambda.Function(this, 'AnalyzerFunction', {
      functionName: 'minutes-analyzer-production',
      runtime: lambda.Runtime.RUBY_3_3,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromAsset('../analyzer/infrastructure/modules/lambda/lambda.zip'),
      timeout: cdk.Duration.seconds(900),
      memorySize: 1024
    });
  }
}
