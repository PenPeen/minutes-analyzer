require_relative 'notion_api_client'
require_relative 'notion_page_builder'
require_relative 'notion_task_manager'

class NotionIntegrationService
  def initialize(api_key, database_id, task_database_id, logger)
    @api_key = api_key
    @database_id = database_id
    @task_database_id = task_database_id
    @logger = logger
    @api_client = NotionApiClient.new(api_key, logger)
    @page_builder = NotionPageBuilder.new(task_database_id, logger)
    @task_manager = NotionTaskManager.new(api_key, task_database_id, logger)
  end

  def create_meeting_page(analysis_result)
    @logger.info("Creating Notion page for meeting minutes")

    # nil安全チェック
    unless analysis_result
      @logger.error("Analysis result is nil")
      return { success: false, error: "Analysis result is nil" }
    end

    @logger.info("Analysis result class: #{analysis_result.class}")
    @logger.info("Analysis result keys: #{analysis_result.keys if analysis_result.respond_to?(:keys)}")

    # ページビルダーを使用してページを構築
    page_data = @page_builder.build_meeting_page(analysis_result, @database_id)
    
    # APIクライアントを使用してページを作成
    response = @api_client.create_page(page_data)

    if response[:success]
      page_id = response[:data]['id']
      @logger.info("Successfully created Notion page: #{page_id}")

      # タスクマネージャーを使用してアクション項目を作成
      task_results = nil
      actions = analysis_result['actions'] || []
      if actions.any? && @task_database_id && !@task_database_id.empty?
        task_results = @task_manager.create_tasks_from_actions(actions, page_id)
      end

      result = { success: true, page_id: page_id, url: response[:data]['url'] }

      # タスク作成結果を含める（失敗がある場合のみ）
      if task_results
        failed_tasks = task_results.select { |t| !t[:success] }
        if failed_tasks && failed_tasks.any?
          result[:task_creation_failures] = failed_tasks
        end
      end

      result
    else
      error_msg = if response[:code]
                    "Notion API error (#{response[:code]}): #{response[:error]}"
                  else
                    "Failed to create Notion page: #{response[:error]}"
                  end
      @logger.error(error_msg)
      { success: false, error: error_msg }
    end
  end

  private

  # 発言統計データを文字列形式にフォーマット
  # Gemini APIから返される発言統計は配列形式
  # @param speaker_stats [Array<Hash>] 発言統計データ
  # @return [String] フォーマット済みの発言統計テキスト
  def format_speaker_stats(speaker_stats)
    result = ""

    # 配列形式のデータを処理
    if speaker_stats.is_a?(Array)
      speaker_stats.each do |speaker|
        next unless speaker.is_a?(Hash)
        name = speaker['name'] || 'Unknown'
        count = speaker['speaking_count'] || 0
        ratio = speaker['speaking_ratio'] || '0%'
        result += "• #{name}: #{count}回 (#{ratio})\n"
      end
    end

    result
  end

  def build_meeting_properties(analysis_result)
    # nil安全な値の取得
    analysis_result ||= {}
    meeting_summary = analysis_result['meeting_summary'] || {}
    decisions = analysis_result['decisions'] || []
    actions = analysis_result['actions'] || []
    health_assessment = analysis_result['health_assessment'] || {}

    properties = {
      "タイトル" => {
        title: [
          {
            text: {
              content: meeting_summary['title'] || "議事録 #{Time.now.strftime('%Y-%m-%d %H:%M')}"
            }
          }
        ]
      },
      "日付" => {
        date: {
          start: meeting_summary['date'] || Time.now.strftime('%Y-%m-%d')
        }
      }
    }

    # 参加者の設定
    if meeting_summary['participants'] && meeting_summary['participants'].any?
      properties["参加者"] = {
        multi_select: meeting_summary['participants'].map { |p| { name: p } }
      }
    end

    # 決定事項とアクション項目は本文に記載するため、プロパティには設定しない

    # 健全性スコアの設定
    if health_assessment['overall_score']
      properties["スコア"] = {
        number: health_assessment['overall_score']
      }
    end

    properties
  end

  def build_page_content(analysis_result)
    content = []

    # ヘッダー
    content << build_header

    # nil安全な値の取得
    analysis_result ||= {}
    decisions = analysis_result['decisions'] || []
    actions = analysis_result['actions'] || []
    health_assessment = analysis_result['health_assessment'] || {}
    participation_analysis = analysis_result['participation_analysis'] || {}
    atmosphere = analysis_result['atmosphere'] || {}
    improvement_suggestions = analysis_result['improvement_suggestions'] || []

    content.concat(build_decisions_section(decisions)) if decisions.any?
    content.concat(build_actions_section(actions)) if actions.any?
    content.concat(build_health_section(health_assessment)) if health_assessment['overall_score']
    content.concat(build_participation_section(participation_analysis)) if participation_analysis['balance_score']
    content.concat(build_atmosphere_section(atmosphere)) if atmosphere['overall_tone']
    content.concat(build_improvements_section(improvement_suggestions)) if improvement_suggestions.any?

    content
  end

  def build_header
    {
      type: "heading_1",
      heading_1: {
        rich_text: [
          {
            type: "text",
            text: { content: "議事録サマリー" }
          }
        ]
      }
    }
  end

  def build_decisions_section(decisions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📌 決定事項" }
          }
        ]
      }
    }

    decisions.each do |decision|
      next unless decision.is_a?(Hash)
      text = "#{decision['content'] || '内容不明'}"

      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: text }
            }
          ]
        }
      }
    end

    section
  end

  def build_actions_section(actions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "✅ アクション項目" }
          }
        ]
      }
    }

    # タスクデータベースが設定されている場合のみ処理
    return section if @task_database_id.to_s.empty?

    total = actions&.size.to_i
    high = actions.to_a.count { |a| a['priority'].to_s.downcase == 'high' }

    # URLは既存ビューURL（環境変数から取得可能な場合）またはDB直URLを使用
    # ハイフン無しのコンパクトIDに変換
    compact_task_db_id = @task_database_id.to_s.gsub('-', '')
    tasks_view_url = ENV['NOTION_TASKS_VIEW_URL'] # 既存ビューURLがあれば使用
    url = tasks_view_url || "https://www.notion.so/#{compact_task_db_id}"

    callout_rich = [
      { type: "text", text: { content: "📊 タスク: #{total}件（高優先度: #{high}件）\n" } },
      { type: "text", text: { content: "→ タスク管理データベースで詳細確認", link: { url: url } } }
    ]

    section << {
      type: "callout",
      callout: {
        rich_text: callout_rich,
        icon: { emoji: "📋" },
        color: "blue_background"
      }
    }

    section
  end

  def build_health_section(health_assessment)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📊 会議の健全性評価" }
          }
        ]
      }
    }

    content = "総合スコア: #{health_assessment['overall_score']}/100\n"

    if health_assessment['contradictions'] && health_assessment['contradictions'].any?
      content += "\n矛盾点:\n"
      health_assessment['contradictions'].each { |c| content += "• #{c}\n" }
    end

    if health_assessment['unresolved_issues'] && health_assessment['unresolved_issues'].any?
      content += "\n未解決課題:\n"
      health_assessment['unresolved_issues'].each { |u| content += "• #{u}\n" }
    end

    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }

    section
  end

  def build_participation_section(participation_analysis)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "👥 参加度分析" }
          }
        ]
      }
    }

    content = "バランススコア: #{participation_analysis['balance_score']}/100\n\n"

    if participation_analysis['speaker_stats']
      content += "発言統計:\n"
      content += format_speaker_stats(participation_analysis['speaker_stats'])
    end

    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }

    section
  end

  def build_atmosphere_section(atmosphere)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "😊 会議の雰囲気" }
          }
        ]
      }
    }

    tone_emoji = case atmosphere['overall_tone']
                 when 'positive' then '😊'
                 when 'negative' then '😟'
                 else '😐'
                 end

    content = "全体的な雰囲気: #{tone_emoji} #{atmosphere['overall_tone']}\n\n"

    if atmosphere['evidence'] && atmosphere['evidence'].any?
      content += "根拠:\n"
      atmosphere['evidence'].each { |e| content += "• #{e}\n" }
    end

    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }

    section
  end

  def build_improvements_section(improvement_suggestions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "💡 改善提案" }
          }
        ]
      }
    }

    improvement_suggestions.each do |suggestion|
      next unless suggestion.is_a?(Hash)
      category_emoji = case suggestion['category']
                      when 'participation' then '👥'
                      when 'time_management' then '⏱️'
                      when 'decision_making' then '🎯'
                      when 'facilitation' then '🎤'
                      else '💡'
                      end

      suggestion_text = suggestion['suggestion'] || '提案内容'
      impact_text = suggestion['expected_impact'] ? " (期待効果: #{suggestion['expected_impact']})" : ""

      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: "#{category_emoji} #{suggestion_text}#{impact_text}" }
            }
          ]
        }
      }
    end

    section
  end

  # Notionタスクページの本文コンテンツを構築
  # @param action [Hash] タスクのアクション情報
  # @return [Array<Hash>] Notion APIのブロック形式のコンテンツ配列
  def build_task_content(action)
    content = []
    add_task_context_section(content, action)
    add_task_steps_section(content, action)
    add_task_details_section(content, action)
    content
  end

  # タスクの背景・文脈セクションを追加
  # @param content [Array] コンテンツ配列
  # @param action [Hash] タスクのアクション情報
  def add_task_context_section(content, action)
    return unless action['task_context'] && !action['task_context'].empty?

    content << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📝 背景・文脈" }
          }
        ]
      }
    }

    content << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: action['task_context'] }
          }
        ]
      }
    }
  end

  # タスクの実行手順セクションを追加
  # @param content [Array] コンテンツ配列
  # @param action [Hash] タスクのアクション情報
  def add_task_steps_section(content, action)
    return unless action['suggested_steps'] && action['suggested_steps'].any?

    content << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📋 実行手順" }
          }
        ]
      }
    }

    action['suggested_steps'].each do |step|
      content << {
        type: "numbered_list_item",
        numbered_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: step }
            }
          ]
        }
      }
    end
  end

  # タスクの詳細情報セクションを追加
  # @param content [Array] コンテンツ配列
  # @param action [Hash] タスクのアクション情報
  def add_task_details_section(content, action)
    content << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "ℹ️ タスク情報" }
          }
        ]
      }
    }

    priority_emoji = case action['priority']
                    when 'high' then '🔴'
                    when 'medium' then '🟡'
                    else '⚪'
                    end

    details = []
    details << "優先度: #{priority_emoji} #{action['priority']}"
    details << "担当者: #{action['assignee']}" if action['assignee']
    details << "期限: #{action['deadline_formatted']}" if action['deadline_formatted']
    details << "作成時刻: #{action['timestamp']}" if action['timestamp']

    content << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: details.join("\n") }
          }
        ]
      }
    }
  end

  def create_tasks_from_actions(actions, meeting_page_id)
    @logger.info("Creating tasks in task database")

    task_results = []
    actions.each do |action|
      next unless action.is_a?(Hash) && action['task']
      result = create_task(action, meeting_page_id)
      task_results << { task: action['task'], success: result[:success], error: result[:error] }
    end

    task_results
  end

  def create_task(action, meeting_page_id)
    uri = URI("#{NOTION_API_BASE_URL}/pages")

    properties = {
      "タスク名" => {
        title: [
          {
            text: {
              content: action['task'] || "タスク"
            }
          }
        ]
      },
      "ステータス" => {
        select: {
          name: "未着手"
        }
      },
      "関連議事録" => {
        relation: [
          {
            id: meeting_page_id
          }
        ]
      }
    }

    # 優先度の設定
    if action['priority']
      priority_map = {
        'high' => '高',
        'medium' => '中',
        'low' => '低'
      }
      properties["優先度"] = {
        select: {
          name: priority_map[action['priority']] || '中'
        }
      }
    end

    # 担当者の設定（テキストフィールドとして設定）
    if action['assignee']
      properties["担当者"] = {
        rich_text: [
          {
            text: {
              content: action['assignee']
            }
          }
        ]
      }
    end

    # 期限の設定（deadlineをパースして日付形式に変換）
    if action['deadline']
      begin
        # 期限が文字列の場合、日付として解析を試みる
        deadline_date = Date.parse(action['deadline'].to_s)
        properties["期限"] = {
          date: {
            start: deadline_date.to_s
          }
        }
      rescue
        @logger.warn("Could not parse deadline: #{action['deadline']}")
      end
    end

    # タスクの本文を構築
    children = build_task_content(action)

    request_body = {
      parent: { database_id: @task_database_id },
      properties: properties,
      children: children
    }

    response = @api_client.create_page(request_body)

    if response[:success]
      @logger.info("Successfully created task: #{action['task']}")
    else
      @logger.error("Failed to create task: #{response[:error]}")
    end

    response
  end

end
