# frozen_string_literal: true

# Configure request timeouts to prevent resource exhaustion
# Rack::Timeout stops processing requests that take too long
if defined?(Rack::Timeout)
  # Set timeout to 15 seconds in production, 30 in development
  Rack::Timeout.timeout = Rails.env.production? ? 15 : 30
  
  # Don't timeout in test environment
  Rack::Timeout.timeout = 0 if Rails.env.test?
  
  # Log timeout errors
  Rack::Timeout::Logger.level = Logger::ERROR
end