# 後方互換性のためのエイリアス
require_relative 'notion_integration_service'

# テストが既存のクラス名を期待しているため
NotionClient = NotionIntegrationService