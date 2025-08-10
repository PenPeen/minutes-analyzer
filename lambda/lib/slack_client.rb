# 後方互換性のためのエイリアス
require_relative 'slack_notification_service'

# テストが既存のクラス名を期待しているため
SlackClient = SlackNotificationService