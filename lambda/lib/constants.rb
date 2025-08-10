# Frozen string literals for better performance
module Constants
  # API Configuration
  module Api
    NOTION_VERSION = '2022-06-28'.freeze
    NOTION_BASE_URL = 'https://api.notion.com/v1'.freeze
    SLACK_BASE_URL = 'https://slack.com/api'.freeze
    
    # Timeouts (in seconds)
    HTTP_READ_TIMEOUT = 30
    HTTP_OPEN_TIMEOUT = 10
    
    # Retry configuration
    MAX_RETRIES = 3
    RETRY_DELAY = 1
  end
  
  # Display limits
  module Display
    MAX_PARTICIPANTS = 3
    MAX_DECISIONS = 3
    MAX_ACTIONS = 3
    MAX_SUGGESTIONS = 3
    MAX_DECISIONS_IN_NOTION = 5
    MAX_ACTIONS_IN_NOTION = 5
  end
  
  # Priority mappings
  module Priority
    LEVELS = {
      'high' => 0,
      'medium' => 1,
      'low' => 2
    }.freeze
    
    EMOJIS = {
      'high' => '🔴',
      'medium' => '🟡',
      'low' => '⚪'
    }.freeze
    
    JAPANESE = {
      'high' => '高',
      'medium' => '中',
      'low' => '低'
    }.freeze
  end
  
  # Tone indicators
  module Tone
    EMOJIS = {
      'positive' => '😊',
      'negative' => '😔',
      'neutral' => '😐'
    }.freeze
  end
  
  # Status values
  module Status
    TASK = '未着手'.freeze
    COMPLETED = 'completed'.freeze
    PARTIAL = 'partial'.freeze
    FAILED = 'failed'.freeze
  end
  
  # Environment defaults
  module Environment
    DEFAULT_LOG_LEVEL = 'INFO'.freeze
    DEFAULT_ENVIRONMENT = 'local'.freeze
  end
  
  # Validation
  module Validation
    MAX_TEXT_LENGTH = 2000
    MAX_TITLE_LENGTH = 200
  end
  
  # User mapping
  module UserMapping
    MAPPING_TIMEOUT = 60
    MAX_THREADS = 10
    API_TIMEOUT = 30
  end
end