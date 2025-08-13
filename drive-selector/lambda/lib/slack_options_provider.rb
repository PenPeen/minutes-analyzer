# frozen_string_literal: true

require_relative 'google_drive_client'

class SlackOptionsProvider
  def initialize
    # 必要に応じて初期化
  end

  # external_select用のオプションを提供
  def provide_file_options(user_id, query)
    # Google Drive検索を実行
    drive_client = GoogleDriveClient.new(user_id)
    
    unless drive_client.authorized?
      return format_unauthorized_response
    end

    # ファイルを検索（最大20件）
    files = drive_client.search_files(query, 20)
    
    if files.empty?
      return format_no_results_response(query)
    end

    # Slack形式にフォーマット
    format_file_options(files)
  end

  private

  # ファイルオプションをSlack形式にフォーマット
  def format_file_options(files)
    options = files.map do |file|
      # ファイル名を適切な長さに調整（75文字まで）
      display_name = truncate_filename(file[:name], 75)
      
      # 最終更新日時を追加
      modified_date = format_date(file[:modified_time])
      display_text = "#{display_name} (#{modified_date})"
      
      {
        text: {
          type: 'plain_text',
          text: display_text
        },
        value: file[:id]
      }
    end

    {
      options: options
    }
  end

  # 認証されていない場合のレスポンス
  def format_unauthorized_response
    {
      options: [
        {
          text: {
            type: 'plain_text',
            text: '⚠️ Google認証が必要です。/meet-transcript コマンドを再実行してください。'
          },
          value: 'unauthorized'
        }
      ]
    }
  end

  # 検索結果がない場合のレスポンス
  def format_no_results_response(query)
    message = if query && !query.empty?
                "「#{query}」に一致するファイルが見つかりませんでした"
              else
                'ファイルが見つかりませんでした'
              end

    {
      options: [
        {
          text: {
            type: 'plain_text',
            text: "🔍 #{message}"
          },
          value: 'no_results'
        }
      ]
    }
  end

  # ファイル名を切り詰める
  def truncate_filename(filename, max_length)
    return filename if filename.length <= max_length
    
    # 拡張子を保持
    extension_match = filename.match(/(\.[^.]+)$/)
    extension = extension_match ? extension_match[1] : ''
    
    if extension.empty?
      # 拡張子がない場合は単純に切り詰め
      filename[0...max_length]
    else
      # 拡張子がある場合は拡張子を保持して切り詰め
      name_without_ext = filename.sub(/\.[^.]+$/, '')
      
      # 拡張子が長すぎる場合は単純に切り詰め
      if extension.length >= max_length
        filename[0...max_length]
      else
        truncated_length = max_length - extension.length - 4 # "..." + "." の分
        
        if truncated_length > 0
          "#{name_without_ext[0...truncated_length]}...#{extension}"
        else
          filename[0...max_length]
        end
      end
    end
  end

  # 日付をフォーマット
  def format_date(datetime_str)
    return '不明' unless datetime_str
    
    begin
      datetime = DateTime.parse(datetime_str)
      # 日本時間に変換（JST = UTC+9）
      jst_datetime = datetime.new_offset('+09:00')
      jst_datetime.strftime('%Y/%m/%d %H:%M')
    rescue => e
      puts "Date parsing error: #{e.message}"
      '不明'
    end
  end
end