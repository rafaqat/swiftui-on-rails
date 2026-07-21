# frozen_string_literal: true

require_relative "lib/view_component/storybook/version"

Gem::Specification.new do |spec|
  spec.name = "view_component_storybook_rails8"
  spec.version = ViewComponent::Storybook::VERSION
  spec.authors = ["Swift Rails Views Team"]
  spec.email = ["team@swiftrailsviews.com"]

  spec.summary = "ViewComponent Storybook fork compatible with Rails 8"
  spec.description = "A fork of view_component-storybook updated to work with Rails 8 and modern Ruby versions"
  spec.homepage = "https://github.com/swiftrailsviews/view_component_storybook_rails8"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `find . -type f -name "*.rb" -o -name "*.md" -o -name "*.txt" -o -name "*.rake" | grep -v "^\\./\\."`.split("\n")
  end
  
  spec.require_paths = ["lib"]

  spec.add_dependency "view_component", ">= 2.2"
  spec.add_dependency "rails", ">= 6.1.0"

  # Remove yard dependency that's causing issues
  # spec.add_dependency "yard", "~> 0.9.25"

  spec.add_development_dependency "rspec", "~> 3.10"
  spec.add_development_dependency "rspec-rails", "~> 8.0"
end