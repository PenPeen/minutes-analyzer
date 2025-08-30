require 'spec_helper'
require_relative '../lib/environment_config'

RSpec.describe EnvironmentConfig do
  let(:logger) { double('logger') }
  
  before do
    allow(logger).to receive(:info)
  end

  describe '#initialize' do
    context '環境変数が設定されていない場合' do
      before do
        ENV.delete('ENVIRONMENT')
      end

      it 'デフォルト値が正しく設定される' do
        config = EnvironmentConfig.new(logger)
        
        expect(config.environment).to eq('local')
      end

      it 'ログ出力が実行される' do
        expect(logger).to receive(:info).with('Environment: local')
        
        EnvironmentConfig.new(logger)
      end
    end

    context '環境変数が設定されている場合' do
      before do
        ENV['ENVIRONMENT'] = 'production'
      end

      after do
        ENV.delete('ENVIRONMENT')
      end

      it '環境変数の値が正しく設定される' do
        config = EnvironmentConfig.new(logger)
        
        expect(config.environment).to eq('production')
      end

      it 'ログ出力が実行される' do
        expect(logger).to receive(:info).with('Environment: production')
        
        EnvironmentConfig.new(logger)
      end
    end

    context 'ロガーが渡されない場合' do
      it 'エラーが発生しない' do
        expect { EnvironmentConfig.new }.not_to raise_error
      end

      it 'ログ出力が実行されない' do
        expect(logger).not_to receive(:info)
        EnvironmentConfig.new(nil)
      end
    end
  end
end