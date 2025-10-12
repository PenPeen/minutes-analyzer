#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AnalyzerStack } from '../lib/analyzer-stack';
import { DriveSelectorStack } from '../lib/drive-selector-stack';
import * as dotenv from 'dotenv';
import * as path from 'path';

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

driveSelectorStack.addDependency(analyzerStack);
