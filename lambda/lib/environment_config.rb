class EnvironmentConfig
  attr_reader :environment, :google_calendar_enabled, :user_mapping_enabled
  
  def initialize(logger = nil)
    @logger = logger
    @environment = ENV.fetch('ENVIRONMENT', 'local')
    @google_calendar_enabled = parse_boolean_env('GOOGLE_CALENDAR_ENABLED', false)
    @user_mapping_enabled = parse_boolean_env('USER_MAPPING_ENABLED', false)
    
    log_configuration if @logger
  end
  
  def user_mapping_enabled?
    @google_calendar_enabled && @user_mapping_enabled
  end
  
  private
  
  def parse_boolean_env(key, default_value)
    value = ENV.fetch(key, default_value.to_s)
    return default_value if value.nil? || value.empty?
    
    %w[true yes 1 on].include?(value.downcase)
  end
  
  def log_configuration
    @logger.info("Google Calendar integration: #{@google_calendar_enabled ? 'enabled' : 'disabled'}")
    @logger.info("User mapping: #{@user_mapping_enabled ? 'enabled' : 'disabled'}")
  end
end