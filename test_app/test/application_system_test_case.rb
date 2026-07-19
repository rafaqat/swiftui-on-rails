require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400] do |options|
    # Enable logging to capture console errors
    options.add_option('goog:loggingPrefs', { browser: 'ALL' })
  end
  
  # DO NOT include ViewComponent::SystemTestHelpers here - it conflicts with Capybara DSL
  # We'll handle ViewComponent rendering separately when needed

  include DemoSystemHelpers

  setup do
    # Selenium retains browser log entries between test examples. Drain them so
    # a test can only fail on console errors produced by its own navigation.
    page.driver.browser.logs.get(:browser)
  end
  
  # Helper to check for browser console errors
  def assert_no_console_errors
    logs = page.driver.browser.logs.get(:browser)
    errors = logs.select { |log| log.level == "SEVERE" }
    
    if errors.any?
      error_messages = errors.map { |e| e.message }.join("\n")
      raise "Browser console errors found:\n#{error_messages}"
    end
  end
  
  # Helper to check if page has error content
  def assert_no_page_errors
    # Check for common error indicators
    assert_no_text "Error rendering component"
    assert_no_text "undefined method"
    assert_no_text "NoMethodError"
    assert_no_text "NameError"
    assert_no_selector ".text-red-600", text: /Error/
  end
  
  # Helper to capture and return console logs
  def console_logs
    page.driver.browser.logs.get(:browser)
  end
  
  # Helper to print all console output for debugging
  def debug_console_output
    logs = console_logs
    puts "\n=== Browser Console Output ==="
    logs.each do |log|
      puts "[#{log.level}] #{log.message}"
    end
    puts "=== End Console Output ===\n"
  end
end
