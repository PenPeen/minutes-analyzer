# frozen_string_literal: true

require 'json'

class SlackModalBuilder
  # ファイル選択モーダルを構築
  def self.file_selector_modal
    {
      type: 'modal',
      callback_id: 'file_selector_modal',
      title: {
        type: 'plain_text',
        text: '📂 ファイル選択',
        emoji: true
      },
      submit: {
        type: 'plain_text',
        text: '分析開始',
        emoji: true
      },
      close: {
        type: 'plain_text',
        text: 'キャンセル',
        emoji: true
      },
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: 'Google Driveから議事録ファイルを選択するか、Google DocsのURLを直接入力してください。'
          }
        },
        {
          type: 'divider'
        },
        {
          type: 'input',
          block_id: 'file_select_block',
          element: {
            type: 'external_select',
            action_id: 'file_select',
            placeholder: {
              type: 'plain_text',
              text: 'ファイル名を入力して検索...',
              emoji: true
            },
            min_query_length: 0
          },
          label: {
            type: 'plain_text',
            text: 'ファイルを選択 📄',
            emoji: true
          },
          hint: {
            type: 'plain_text',
            text: 'Meet Recordingsフォルダから最新順で表示されます'
          },
          optional: true
        },
        {
          type: 'input',
          block_id: 'url_input_block',
          element: {
            type: 'plain_text_input',
            action_id: 'url_input',
            placeholder: {
              type: 'plain_text',
              text: 'https://docs.google.com/document/d/FILE_ID/edit'
            }
          },
          label: {
            type: 'plain_text',
            text: 'または、Google DocsのURLを入力 🔗',
            emoji: true
          },
          hint: {
            type: 'plain_text',
            text: 'Google DocsやDriveの直接URLを貼り付けてください'
          },
          optional: true
        },
        {
          type: 'section',
          block_id: 'options_block',
          text: {
            type: 'mrkdwn',
            text: '追加オプション'
          },
          accessory: {
            type: 'checkboxes',
            action_id: 'analysis_options',
            options: [
              {
                text: {
                  type: 'mrkdwn',
                  text: '📝 Notionに自動保存（分析結果をNotionデータベースに保存）'
                },
                value: 'save_to_notion'
              }
            ],
            initial_options: [
              {
                text: {
                  type: 'mrkdwn',
                  text: '📝 Notionに自動保存（分析結果をNotionデータベースに保存）'
                },
                value: 'save_to_notion'
              }
            ]
          }
        }
      ]
    }
  end

  # 処理中モーダル
  def self.processing_modal
    {
      type: 'modal',
      callback_id: 'processing_modal',
      title: {
        type: 'plain_text',
        text: '⏳ 処理中',
        emoji: true
      },
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: '*議事録を分析しています...*\n\n処理が完了したらSlackでお知らせします。'
          }
        },
        {
          type: 'image',
          image_url: 'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif',
          alt_text: 'Processing...'
        },
        {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: '⏱️ 通常1-2分で完了します'
            }
          ]
        }
      ]
    }
  end

  # エラーモーダル
  def self.error_modal(error_message)
    {
      type: 'modal',
      callback_id: 'error_modal',
      title: {
        type: 'plain_text',
        text: '❌ エラー',
        emoji: true
      },
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: '*処理中にエラーが発生しました*'
          }
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "```\n#{error_message}\n```"
          }
        },
        {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: '問題が続く場合は、管理者にお問い合わせください。'
            }
          ]
        }
      ]
    }
  end

  # 成功モーダル
  def self.success_modal(file_name)
    {
      type: 'modal',
      callback_id: 'success_modal',
      title: {
        type: 'plain_text',
        text: '✅ 完了',
        emoji: true
      },
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*分析リクエストを受け付けました*\n\n以下のファイルの分析を開始しました："
          }
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "📄 `#{file_name}`"
          }
        },
        {
          type: 'divider'
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: '🔔 *次のステップ*\n• 分析が完了したらSlackチャンネルに通知されます\n• Notionに結果が自動保存されます（有効な場合）'
          }
        },
        {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: '⏱️ 予想処理時間: 1-2分'
            }
          ]
        }
      ]
    }
  end
end
