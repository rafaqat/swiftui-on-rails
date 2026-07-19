# SimpleCov configuration. Coverage starts explicitly from test/test_helper.rb.
SimpleCov.configure do
  root File.expand_path("..", __dir__)
  coverage_dir "test_app/tmp/coverage"

  # Custom configuration for SwiftUI Rails
  cover "lib/**/*.rb", "test_app/app/**/*.rb", "view_component_storybook_rails8/lib/**/*.rb"

  skip "/test/"
  skip "/config/"
  skip "/db/"
  skip "/vendor/"
  skip "/.bundle/"
  
  # Group files for better organization
  group "Components", "test_app/app/components"
  group "Controllers", "test_app/app/controllers"
  group "Helpers", "test_app/app/helpers"
  group "Models", "test_app/app/models"
  group "Storybook fork", "view_component_storybook_rails8/lib"
  group "SwiftUI Rails", proc { |src| src.filename.include?("/swift_ui_rails/") }
  
  # Enable branch coverage
  enable_coverage :branch
  
  # Generate HTML report
  formatter SimpleCov::Formatter::HTMLFormatter
end
