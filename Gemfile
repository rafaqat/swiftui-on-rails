source "https://rubygems.org"

ruby ">= 3.0.0"

gemspec

# Runtime dependencies
gem "concurrent-ruby", "~> 1.2" # For thread-safe data structures

group :development, :test do
  gem "sqlite3"
  gem "puma"
  gem "tailwindcss-rails"
  gem "debug"
  
  # SECURITY: Add security linting and scanning tools
  gem "rubocop", "~> 1.50", require: false
  gem "rubocop-rails", "~> 2.19", require: false
  gem "rubocop-rails-omakase", require: false
  gem "brakeman", "~> 6.0", require: false # Security scanner for Rails
  gem "bundler-audit", "~> 0.9", require: false # Dependency security scanner
end