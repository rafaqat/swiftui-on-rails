# frozen_string_literal: true

require_relative "lib/swift_ui_rails/version"

Gem::Specification.new do |spec|
  spec.name = "swift_ui_rails"
  spec.version = SwiftUIRails::VERSION
  spec.authors = ["SwiftUI Rails Contributors"]
  spec.email = ["contributors@swiftuirails.org"]

  spec.summary = "SwiftUI-inspired DSL for building Rails views with Tailwind CSS"
  spec.description = "A declarative, component-based view system for Rails that combines SwiftUI's intuitive API with Tailwind CSS utilities and ViewComponent architecture"
  spec.homepage = "https://github.com/rafaqat/SwiftUI-on-Rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rafaqat/SwiftUI-on-Rails"
  spec.metadata["changelog_uri"] = "https://github.com/rafaqat/SwiftUI-on-Rails/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://swiftuirails.org/docs"
  spec.metadata["bug_tracker_uri"] = "https://github.com/rafaqat/SwiftUI-on-Rails/issues"

  # Keep the release manifest independent of Git and of files generated in a
  # maintainer's checkout. In particular, never package the test application,
  # a previously built .gem, coverage output, or deleted entries still present
  # in the Git index.
  spec.files = Dir.chdir(__dir__) do
    Dir[
      "{lib,docs}/**/*",
      "CHANGELOG.md",
      "README.md",
      "SECURITY.md",
      "LICENSE*"
    ].select { |path| File.file?(path) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "rails", ">= 6.1.0"
  spec.add_dependency "view_component", "~> 3.0"
  spec.add_dependency "turbo-rails", ">= 1.0"
  spec.add_dependency "concurrent-ruby", "~> 1.2" # For thread-safe data structures
  spec.add_dependency "nokogiri", "~> 1.15" # For safe HTML parsing
  spec.add_dependency "marcel", "~> 1.0" # For server-side document content inspection

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "standard", ">= 1.35.1"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "capybara", "~> 3.0"
end
