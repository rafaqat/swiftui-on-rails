# frozen_string_literal: true

require "test_helper"
require "rake"
require "stringio"
require "tempfile"

unless Rake::Task.task_defined?("swift_ui:language:manifest")
  Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
  load Rails.root.join("lib/tasks/swift_ui.rake")
end

class SwiftUiPlaygroundTasksTest < ActiveSupport::TestCase
  test "language manifest exposes the compact generation vocabulary" do
    stdout, stderr = invoke_task("swift_ui:language:manifest", { "COMPACT" => "1" })
    manifest = JSON.parse(stdout)

    assert_empty stderr
    assert_equal Showcase::Playground::LanguageCatalog::VERSION, manifest.fetch("language_version")
    assert manifest.fetch("builders").key?("text")
    assert manifest.fetch("modifiers").key?("text_style")
    refute manifest.fetch("modifiers").key?("text_color")
  end

  test "playground format writes canonical source to stdout" do
    stdout, stderr = invoke_task(
      "swift_ui:playground:format",
      { "SOURCE" => "-" },
      stdin: 'vstack(spacing:8){text("Hello").text_style(:headline)}'
    )

    assert_empty stderr
    assert_equal <<~'RUBY', stdout
      vstack(spacing: 8) do
        text("Hello")
          .text_style(:headline)
      end
    RUBY
  end

  test "artifact verify checks a durable artifact and returns canonical source" do
    example = Showcase::Playground::Examples.all.first
    result = Showcase::Playground::Runner.call(
      source: example.source,
      data_json: example.data_json,
      view_context: ApplicationController.new.view_context
    )
    assert result.success?, result.diagnostics.inspect

    Tempfile.create([ "playground-artifact", ".json" ]) do |file|
      file.write(result.artifact.to_json)
      file.flush

      stdout, stderr = invoke_task("swift_ui:artifact:verify", { "ARTIFACT" => file.path })
      verification = JSON.parse(stdout)

      assert_empty stderr
      assert verification.fetch("ok")
      assert_includes verification.fetch("canonical_source"), "vstack"
    end
  end

  test "reliability report exposes all correctness and efficiency gates" do
    stdout, stderr = invoke_task("swift_ui:reliability:report")
    report = JSON.parse(stdout)
    metrics = report.fetch("metrics")

    assert_empty stderr
    assert report.fetch("ok")
    assert_equal "recorded_candidate_language_conformance", metrics.fetch("measurement_scope")
    assert_equal 1.0, metrics.fetch("recorded_candidate_validity_rate")
    assert_equal 1.0, metrics.fetch("golden_repair_contract_rate")
    assert_nil metrics.fetch("model_first_pass_validity_rate")
    assert_equal 1.0, metrics.fetch("semantic_snapshot_accuracy")
    assert_equal 1.0, metrics.fetch("accessibility_rate")
    assert_equal 1.0, metrics.fetch("unsafe_construct_rejection_rate")
    assert metrics.dig("context_efficiency", "passed")
    assert metrics.dig("context_efficiency", "executable_constraints_preserved")
    assert_operator metrics.dig("context_efficiency", "compact_generation_context_bytes"), :<,
      metrics.dig("context_efficiency", "full_catalog_bytes")
  end

  test "token report preserves exact signed results and the unexecuted provider boundary" do
    stdout, stderr = invoke_task("swift_ui:tokens:report")
    report = JSON.parse(stdout)

    assert_empty stderr
    assert report.fetch("ok")
    assert_equal true, report.dig("methodology", "tokenizer", "exact")
    assert_equal "o200k_base", report.dig("methodology", "tokenizer", "encoding")
    assert_equal "not_run", report.dig("methodology", "provider_model_execution")

    %w[view_source authored_production_closure].each do |scope|
      react = report.dig("summary", "react_rails", scope, "tokens")
      swift = report.dig("summary", "swift_ui_rails", scope, "tokens")
      assert_equal react - swift, report.dig("summary", "savings", scope, "tokens")
    end
  end

  private

  def invoke_task(name, environment = {}, stdin: "")
    previous_environment = environment.to_h { |key, _value| [ key, ENV[key] ] }
    previous_stdin = $stdin
    environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    $stdin = StringIO.new(stdin)

    task = Rake::Task[name]
    task.reenable
    capture_io { task.invoke }
  ensure
    $stdin = previous_stdin
    previous_environment&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
