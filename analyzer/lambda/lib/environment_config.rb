class EnvironmentConfig
  attr_reader :environment
  
  def initialize(logger = nil)
    @logger = logger
    @environment = ENV.fetch('ENVIRONMENT', 'local')
    
    log_configuration if @logger
  end
  
  private
  
  def log_configuration
    @logger.info("Environment: #{@environment}")
  end
end