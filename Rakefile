# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

run_in_test_app = lambda do |*command|
  command_environment = command.first.is_a?(Hash) ? command.shift.dup : {}

  # `bundle exec rake` pins the parent Ruby at the front of PATH. Restore the
  # version-manager path before spawning so test_app/.ruby-version is honored.
  if ENV["RBENV_ORIG_PATH"].to_s != ""
    command_environment["PATH"] = ENV.fetch("RBENV_ORIG_PATH")
    command_environment["RBENV_VERSION"] = nil
    command_environment["RBENV_DIR"] = nil
  end

  Bundler.with_unbundled_env do
    Dir.chdir(File.expand_path("test_app", __dir__)) do
      sh(command_environment, *command)
    end
  end
end

test_environment = {
  "PARALLEL_WORKERS" => ENV.fetch("PARALLEL_WORKERS", "1")
}.freeze

namespace :test do
  desc "Run the Rails unit and integration tests"
  task :rails do
    run_in_test_app.call(test_environment, "bin/rails", "test")
  end

  desc "Run the Rails browser system tests"
  task :system do
    run_in_test_app.call(test_environment, "bin/rails", "test:system")
  end

  desc "Run all behavioral tests"
  task all: %i[rails system]
end

namespace :security do
  desc "Run all security checks"
  task all: %i[tests brakeman audit importmap]

  desc "Run the security regression tests"
  task :tests do
    run_in_test_app.call(test_environment, "bin/rails", "test", "test/security")
  end

  desc "Run the repository RuboCop configuration"
  task :rubocop do
    sh "bundle exec rubocop"
  end

  desc "Run Brakeman security scanner"
  task :brakeman do
    run_in_test_app.call(
      "bundle", "exec", "brakeman", "--confidence-level", "2", "--no-pager"
    )
  end

  desc "Run bundler-audit dependency scanner"
  task :audit do
    run_in_test_app.call("bundle", "exec", "bundle-audit", "check", "--update")
  end

  desc "Run importmap's JavaScript package audit"
  task :importmap do
    run_in_test_app.call("bin/importmap", "audit")
  end

  desc "Run the behavioral thread-safety regression tests"
  task :thread_safety do
    run_in_test_app.call(
      test_environment,
      "bin/rails", "test", "test/security/thread_safety_test.rb"
    )
  end
end

task default: "test:all"

desc "Open an IRB console with SwiftUIRails loaded"
task :console do
  require "irb"
  require "swift_ui_rails"

  # Load Rails environment if available
  if File.exist?("test_app/config/environment.rb")
    puts "Loading Rails test app environment..."
    require_relative "test_app/config/environment"
  end

  # Clear ARGV to prevent IRB from trying to parse rake args
  ARGV.clear

  # Start IRB session
  puts "Starting SwiftUIRails console..."
  puts "SwiftUIRails version: #{SwiftUIRails::VERSION}"

  IRB.start
rescue LoadError => e
  puts "Error loading required libraries: #{e.message}"
  puts "Please ensure all dependencies are installed with: bundle install"
  exit 1
rescue => e
  puts "Error starting console: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
