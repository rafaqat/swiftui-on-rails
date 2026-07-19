# frozen_string_literal: true

require "test_helper"

class SingleRuntimeContractTest < ActiveSupport::TestCase
  PROJECT_ROOT = Rails.root.parent.freeze
  ALLOWED_APPLICATION_JAVASCRIPT = %w[
    app/javascript/application.js
    app/javascript/swift_ui_render_patch.js
    app/javascript/swift_ui_runtime.js
  ].freeze
  ALLOWED_GENERATOR_JAVASCRIPT = %w[
    swift_ui_render_patch.js
    swift_ui_runtime.js
  ].freeze
  APPLICATION_UI_DIRECTORIES = %w[
    app/components
    app/helpers
    app/services
    app/views
    test/components/stories
  ].freeze
  GENERATOR_UI_DIRECTORIES = %w[
    lib/generators/swift_ui_rails/component/templates
    lib/generators/swift_ui_rails/install/templates
    lib/generators/swift_ui_rails/stories/templates
  ].freeze

  test "Stimulus is absent from dependencies imports and generated applications" do
    paths = [
      PROJECT_ROOT.join("swift_ui_rails.gemspec"),
      PROJECT_ROOT.join("Gemfile.lock"),
      Rails.root.join("Gemfile"),
      Rails.root.join("Gemfile.lock"),
      Rails.root.join("config/importmap.rb"),
      Rails.root.join("app/javascript/application.js"),
      PROJECT_ROOT.join("lib/generators/swift_ui_rails/install/install_generator.rb")
    ]

    paths.each do |path|
      refute_match(/stimulus/i, path.read, "#{path.relative_path_from(PROJECT_ROOT)} still references Stimulus")
    end
  end

  test "applications ship one framework-owned browser runtime" do
    application_files = Rails.root.glob("app/**/*.{js,mjs,ts,jsx,tsx}").map do |path|
      path.relative_path_from(Rails.root).to_s
    end.sort
    generator_files = PROJECT_ROOT.glob("lib/generators/swift_ui_rails/install/templates/*.js").map(&:basename).map(&:to_s).sort

    assert_equal ALLOWED_APPLICATION_JAVASCRIPT, application_files
    assert_equal ALLOWED_GENERATOR_JAVASCRIPT, generator_files

    entrypoint = Rails.root.join("app/javascript/application.js").read
    assert_includes entrypoint, 'import "swift_ui_runtime"'
    refute_match(/import\s+["']controllers|motion_stream_transitions/, entrypoint)
  end

  test "checked-in UI source cannot declare a second JavaScript application model" do
    application_paths = APPLICATION_UI_DIRECTORIES.flat_map do |directory|
      Rails.root.glob("#{directory}/**/*.{rb,erb}")
    end
    generator_paths = GENERATOR_UI_DIRECTORIES.flat_map do |directory|
      PROJECT_ROOT.glob("#{directory}/**/*.{rb,erb}")
    end
    source_paths = application_paths + generator_paths
    forbidden = {
      /data-controller\s*=/ => "data-controller",
      /data-action\s*=/ => "data-action",
      /data-[a-z0-9_-]+-target\s*=/i => "controller target attribute",
      /["']data-controller["']\s*=>/ => "data-controller hash key",
      /["']data-action["']\s*=>/ => "data-action hash key",
      /["']data-[a-z0-9_-]+-target["']\s*=>/i => "controller target hash key",
      /\bcontroller:\s*["']/ => "controller data key",
      /\baction:\s*["'][^"']*->/ => "controller callback string",
      /\.stimulus_(?:controller|action|target|param)\b/ => "legacy DSL modifier",
      /\b[a-z0-9_]+_target:\s*["']/ => "controller target key",
      /\bdata_playground_action\b|data-playground-action/i => "inert playground action metadata"
    }

    violations = source_paths.flat_map do |path|
      source = path.read
      forbidden.filter_map do |pattern, label|
        next unless source.match?(pattern)

        "#{path.relative_path_from(PROJECT_ROOT)}: #{label}"
      end
    end

    assert_empty violations, "Application JavaScript metadata remains:\n#{violations.join("\n")}"
  end

  test "the checked-in LLM contract requires Ruby and RenderIR authority" do
    prompt = PROJECT_ROOT.join("CLAUDE.md").read
    assistant_contract = Rails.root.join("app/services/showcase/playground/assistant_contract.rb").read

    assert_includes prompt, "Ruby plus RenderIR is the complete application programming model"
    assert_includes prompt, "RenderIR"
    assert_includes assistant_contract, "Never generate JavaScript"
    assert_includes assistant_contract, "protocol interpreter"
  end
end
