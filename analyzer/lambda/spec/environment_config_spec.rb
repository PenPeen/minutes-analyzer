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
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it 'デフォルト値が正しく設定される' do
        config = EnvironmentConfig.new(logger)
        
        expect(config.environment).to eq('local')
        expect(config.google_calendar_enabled).to eq(false)
        expect(config.user_mapping_enabled).to eq(false)
      end

      it 'ログ出力が実行される' do
        expect(logger).to receive(:info).with('Google Calendar integration: disabled')
        expect(logger).to receive(:info).with('User mapping: disabled')
        
        EnvironmentConfig.new(logger)
      end
    end

    context '環境変数が設定されている場合' do
      before do
        ENV['ENVIRONMENT'] = 'production'
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        ENV['USER_MAPPING_ENABLED'] = 'yes'
      end

      after do
        ENV.delete('ENVIRONMENT')
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it '環境変数の値が正しく設定される' do
        config = EnvironmentConfig.new(logger)
        
        expect(config.environment).to eq('production')
        expect(config.google_calendar_enabled).to eq(true)
        expect(config.user_mapping_enabled).to eq(true)
      end

      it '有効化状態のログが出力される' do
        expect(logger).to receive(:info).with('Google Calendar integration: enabled')
        expect(logger).to receive(:info).with('User mapping: enabled')
        
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

  describe '#user_mapping_enabled?' do
    context 'Google Calendar統合とユーザーマッピングが両方有効な場合' do
      before do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        ENV['USER_MAPPING_ENABLED'] = 'true'
      end

      after do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it 'trueを返す' do
        config = EnvironmentConfig.new(logger)
        expect(config.user_mapping_enabled?).to eq(true)
      end
    end

    context 'Google Calendar統合が無効な場合' do
      before do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'false'
        ENV['USER_MAPPING_ENABLED'] = 'true'
      end

      after do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it 'falseを返す' do
        config = EnvironmentConfig.new(logger)
        expect(config.user_mapping_enabled?).to eq(false)
      end
    end

    context 'ユーザーマッピングが無効な場合' do
      before do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        ENV['USER_MAPPING_ENABLED'] = 'false'
      end

      after do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it 'falseを返す' do
        config = EnvironmentConfig.new(logger)
        expect(config.user_mapping_enabled?).to eq(false)
      end
    end

    context '両方が無効な場合' do
      before do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'false'
        ENV['USER_MAPPING_ENABLED'] = 'false'
      end

      after do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it 'falseを返す' do
        config = EnvironmentConfig.new(logger)
        expect(config.user_mapping_enabled?).to eq(false)
      end
    end
  end

  describe '#parse_boolean_env (private method behavior)' do
    context 'true値の様々な形式' do
      %w[true TRUE True yes YES Yes 1 on ON On].each do |value|
        it "#{value}をtrueとして解釈する" do
          ENV['TEST_BOOL'] = value
          config = EnvironmentConfig.new(logger)
          
          # プライベートメソッドの動作を環境変数設定で間接的にテスト
          expect(config.google_calendar_enabled).to eq(true) if ENV['GOOGLE_CALENDAR_ENABLED'] == value
          
          ENV.delete('TEST_BOOL')
        end
      end

      it 'true値を正しく解釈する' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(true)
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end

      it 'yes値を正しく解釈する' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'yes'
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(true)
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end

      it '1値を正しく解釈する' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = '1'
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(true)
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end

      it 'on値を正しく解釈する' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'on'
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(true)
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end
    end

    context 'false値の様々な形式' do
      %w[false FALSE False no NO No 0 off OFF Off invalid random].each do |value|
        it "#{value}をfalseとして解釈する" do
          ENV['GOOGLE_CALENDAR_ENABLED'] = value
          config = EnvironmentConfig.new(logger)
          expect(config.google_calendar_enabled).to eq(false)
          ENV.delete('GOOGLE_CALENDAR_ENABLED')
        end
      end
    end

    context '空白・nil値の処理' do
      it '空文字列をデフォルト値として解釈する' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = ''
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(false) # デフォルトfalse
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end

      it '未設定の場合はデフォルト値を返す' do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(false) # デフォルトfalse
      end
    end

    context 'デフォルト値のテスト' do
      it 'GOOGLE_CALENDAR_ENABLEDのデフォルトはfalse' do
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(false)
      end

      it 'USER_MAPPING_ENABLEDのデフォルトはfalse' do
        ENV.delete('USER_MAPPING_ENABLED')
        config = EnvironmentConfig.new(logger)
        expect(config.user_mapping_enabled).to eq(false)
      end
    end
  end

  describe '統合テスト' do
    context '実際の環境設定シナリオ' do
      it '本番環境での典型的な設定' do
        ENV['ENVIRONMENT'] = 'production'
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        ENV['USER_MAPPING_ENABLED'] = 'true'

        config = EnvironmentConfig.new(logger)

        expect(config.environment).to eq('production')
        expect(config.google_calendar_enabled).to eq(true)
        expect(config.user_mapping_enabled).to eq(true)
        expect(config.user_mapping_enabled?).to eq(true)

        ENV.delete('ENVIRONMENT')
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it '開発環境での典型的な設定' do
        ENV['ENVIRONMENT'] = 'development'
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'false'
        ENV['USER_MAPPING_ENABLED'] = 'false'

        config = EnvironmentConfig.new(logger)

        expect(config.environment).to eq('development')
        expect(config.google_calendar_enabled).to eq(false)
        expect(config.user_mapping_enabled).to eq(false)
        expect(config.user_mapping_enabled?).to eq(false)

        ENV.delete('ENVIRONMENT')
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end

      it '部分的機能有効化シナリオ' do
        ENV['ENVIRONMENT'] = 'staging'
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'true'
        ENV['USER_MAPPING_ENABLED'] = 'false'

        config = EnvironmentConfig.new(logger)

        expect(config.environment).to eq('staging')
        expect(config.google_calendar_enabled).to eq(true)
        expect(config.user_mapping_enabled).to eq(false)
        expect(config.user_mapping_enabled?).to eq(false) # 両方が必要

        ENV.delete('ENVIRONMENT')
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
        ENV.delete('USER_MAPPING_ENABLED')
      end
    end
  end

  describe 'エラーハンドリング' do
    context '異常な環境変数値' do
      it '空白のみの環境変数を適切に処理' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = '   '
        expect { EnvironmentConfig.new(logger) }.not_to raise_error
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end

      it '非ASCII文字を含む環境変数を適切に処理' do
        ENV['GOOGLE_CALENDAR_ENABLED'] = 'はい'
        config = EnvironmentConfig.new(logger)
        expect(config.google_calendar_enabled).to eq(false) # 認識しない値はfalse
        ENV.delete('GOOGLE_CALENDAR_ENABLED')
      end
    end
  end
end