require 'spec_helper'
require_relative '../lib/constants'

RSpec.describe Constants do
  describe 'モジュール構造の検証' do
    it 'すべてのサブモジュールが定義されている' do
      expect(Constants::Api).to be_a(Module)
      expect(Constants::Display).to be_a(Module)
      expect(Constants::Priority).to be_a(Module)
      expect(Constants::Tone).to be_a(Module)
      expect(Constants::Status).to be_a(Module)
      expect(Constants::Environment).to be_a(Module)
      expect(Constants::Validation).to be_a(Module)
    end
  end

  describe 'Constants::Api' do
    context 'API設定値の検証' do
      it 'NotionとSlackのベースURLが正しく設定されている' do
        expect(Constants::Api::NOTION_VERSION).to eq('2022-06-28')
        expect(Constants::Api::NOTION_BASE_URL).to eq('https://api.notion.com/v1')
        expect(Constants::Api::SLACK_BASE_URL).to eq('https://slack.com/api')
      end

      it 'HTTPタイムアウト値が適切に設定されている' do
        expect(Constants::Api::HTTP_READ_TIMEOUT).to eq(30)
        expect(Constants::Api::HTTP_OPEN_TIMEOUT).to eq(10)
      end

      it 'リトライ設定が適切に設定されている' do
        expect(Constants::Api::MAX_RETRIES).to eq(3)
        expect(Constants::Api::RETRY_DELAY).to eq(1)
      end
    end

    context 'frozen文字列の検証' do
      it 'API URLが凍結されている' do
        expect(Constants::Api::NOTION_VERSION).to be_frozen
        expect(Constants::Api::NOTION_BASE_URL).to be_frozen
        expect(Constants::Api::SLACK_BASE_URL).to be_frozen
      end
    end
  end

  describe 'Constants::Display' do
    context '表示制限値の検証' do
      it '各項目の最大表示数が適切に設定されている' do
        expect(Constants::Display::MAX_PARTICIPANTS).to eq(3)
        expect(Constants::Display::MAX_DECISIONS).to eq(3)
        expect(Constants::Display::MAX_ACTIONS).to eq(3)
        expect(Constants::Display::MAX_SUGGESTIONS).to eq(3)
      end

      it 'Notion表示制限が通常制限より大きい' do
        expect(Constants::Display::MAX_DECISIONS_IN_NOTION).to eq(5)
        expect(Constants::Display::MAX_ACTIONS_IN_NOTION).to eq(5)
        expect(Constants::Display::MAX_DECISIONS_IN_NOTION).to be > Constants::Display::MAX_DECISIONS
        expect(Constants::Display::MAX_ACTIONS_IN_NOTION).to be > Constants::Display::MAX_ACTIONS
      end

      it '表示制限値はすべて正の整数' do
        expect(Constants::Display::MAX_PARTICIPANTS).to be_a(Integer).and be > 0
        expect(Constants::Display::MAX_DECISIONS).to be_a(Integer).and be > 0
        expect(Constants::Display::MAX_ACTIONS).to be_a(Integer).and be > 0
        expect(Constants::Display::MAX_SUGGESTIONS).to be_a(Integer).and be > 0
      end
    end
  end

  describe 'Constants::Priority' do
    context '優先度レベルの検証' do
      it '適切な優先度レベルとソート順が設定されている' do
        expect(Constants::Priority::LEVELS).to eq({
          'high' => 0,
          'medium' => 1,
          'low' => 2
        })
      end

      it '優先度マッピングが凍結されている' do
        expect(Constants::Priority::LEVELS).to be_frozen
      end

      it 'すべての優先度に対応する絵文字が設定されている' do
        Constants::Priority::LEVELS.keys.each do |priority|
          expect(Constants::Priority::EMOJIS[priority]).to be_a(String)
          expect(Constants::Priority::EMOJIS[priority].length).to be > 0
        end
      end

      it 'すべての優先度に対応する日本語表記が設定されている' do
        Constants::Priority::LEVELS.keys.each do |priority|
          expect(Constants::Priority::JAPANESE[priority]).to be_a(String)
          expect(Constants::Priority::JAPANESE[priority].length).to be > 0
        end
      end

      it '優先度絵文字マッピングが凍結されている' do
        expect(Constants::Priority::EMOJIS).to be_frozen
        expect(Constants::Priority::JAPANESE).to be_frozen
      end
    end

    context '優先度の一貫性検証' do
      it '全ての優先度マッピングが同じキーを持つ' do
        level_keys = Constants::Priority::LEVELS.keys.sort
        emoji_keys = Constants::Priority::EMOJIS.keys.sort
        japanese_keys = Constants::Priority::JAPANESE.keys.sort

        expect(emoji_keys).to eq(level_keys)
        expect(japanese_keys).to eq(level_keys)
      end
    end
  end

  describe 'Constants::Tone' do
    context '雰囲気絵文字の検証' do
      it '適切な雰囲気の絵文字が設定されている' do
        expect(Constants::Tone::EMOJIS).to include(
          'positive' => '😊',
          'negative' => '😔',
          'neutral' => '😐'
        )
      end

      it '雰囲気絵文字マッピングが凍結されている' do
        expect(Constants::Tone::EMOJIS).to be_frozen
      end

      it 'すべての雰囲気に絵文字が設定されている' do
        %w[positive negative neutral].each do |tone|
          expect(Constants::Tone::EMOJIS[tone]).to be_a(String)
          expect(Constants::Tone::EMOJIS[tone].length).to be > 0
        end
      end
    end
  end

  describe 'Constants::Status' do
    context 'ステータス値の検証' do
      it '適切なステータス値が設定されている' do
        expect(Constants::Status::TASK).to eq('未着手')
        expect(Constants::Status::COMPLETED).to eq('completed')
        expect(Constants::Status::PARTIAL).to eq('partial')
        expect(Constants::Status::FAILED).to eq('failed')
      end

      it 'ステータス値が凍結されている' do
        expect(Constants::Status::TASK).to be_frozen
        expect(Constants::Status::COMPLETED).to be_frozen
        expect(Constants::Status::PARTIAL).to be_frozen
        expect(Constants::Status::FAILED).to be_frozen
      end
    end
  end

  describe 'Constants::Environment' do
    context '環境設定デフォルト値の検証' do
      it '適切なデフォルト値が設定されている' do
        expect(Constants::Environment::DEFAULT_LOG_LEVEL).to eq('INFO')
        expect(Constants::Environment::DEFAULT_ENVIRONMENT).to eq('local')
      end

      it 'デフォルト値が凍結されている' do
        expect(Constants::Environment::DEFAULT_LOG_LEVEL).to be_frozen
        expect(Constants::Environment::DEFAULT_ENVIRONMENT).to be_frozen
      end
    end
  end

  describe 'Constants::Validation' do
    context 'バリデーション制限値の検証' do
      it '適切な制限値が設定されている' do
        expect(Constants::Validation::MAX_TEXT_LENGTH).to eq(2000)
        expect(Constants::Validation::MAX_TITLE_LENGTH).to eq(200)
      end

      it '制限値は正の整数' do
        expect(Constants::Validation::MAX_TEXT_LENGTH).to be_a(Integer).and be > 0
        expect(Constants::Validation::MAX_TITLE_LENGTH).to be_a(Integer).and be > 0
      end

      it 'タイトル制限がテキスト制限より小さい' do
        expect(Constants::Validation::MAX_TITLE_LENGTH).to be < Constants::Validation::MAX_TEXT_LENGTH
      end
    end
  end


  describe '境界値テスト' do
    context 'タイムアウト値の境界値検証' do
      it 'HTTPタイムアウトが実用的な範囲内' do
        expect(Constants::Api::HTTP_READ_TIMEOUT).to be_between(5, 120)
        expect(Constants::Api::HTTP_OPEN_TIMEOUT).to be_between(1, 30)
      end

    end

    context '表示制限の境界値検証' do
      it '表示制限が実用的な範囲内' do
        expect(Constants::Display::MAX_PARTICIPANTS).to be_between(1, 10)
        expect(Constants::Display::MAX_DECISIONS).to be_between(1, 10)
        expect(Constants::Display::MAX_ACTIONS).to be_between(1, 10)
      end
    end
  end

  describe '設定の一貫性検証' do
    context 'リトライ設定の一貫性' do
      it 'リトライ回数と遅延が適切な組み合わせ' do
        total_retry_time = Constants::Api::MAX_RETRIES * Constants::Api::RETRY_DELAY
        expect(total_retry_time).to be < Constants::Api::HTTP_READ_TIMEOUT
      end
    end

    context '表示制限の一貫性' do
      it 'Notion表示制限が通常表示制限以上' do
        expect(Constants::Display::MAX_DECISIONS_IN_NOTION).to be >= Constants::Display::MAX_DECISIONS
        expect(Constants::Display::MAX_ACTIONS_IN_NOTION).to be >= Constants::Display::MAX_ACTIONS
      end
    end
  end
end