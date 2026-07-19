# frozen_string_literal: true

require "test_helper"

# Pins the corpus-wide clean state: every component and story passes
# swift_ui:lint with zero error-severity findings, and every curated
# playground example compiles through the SourceCompiler. A regression here
# means a phantom modifier, hallucinated style value, or broken render has
# re-entered the few-shot corpus.
class CorpusLintTest < ActiveSupport::TestCase
  CORPUS_GLOBS = [
    "app/components/**/*_component.rb",
    "test/components/stories/*_stories.rb"
  ].freeze

  test "the whole component and story corpus lints without errors" do
    files = CORPUS_GLOBS.flat_map { |glob| Dir.glob(Rails.root.join(glob)) }
                        .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }

    assert_operator files.length, :>=, 50, "corpus glob looks broken"

    offenders = files.flat_map do |file|
      SwiftUi::Lint.call(file)
                   .select { |diagnostic| diagnostic.severity == "error" }
                   .map { |diagnostic| "#{file}:#{diagnostic.line} [#{diagnostic.code}] #{diagnostic.message.to_s.first(160)}" }
    end

    assert_empty offenders, "Corpus lint errors:\n#{offenders.join("\n")}"
  end

  test "every curated playground example compiles clean" do
    examples = Showcase::Playground::Examples.all
    assert_operator examples.length, :>=, 1

    view_context = ApplicationController.new.view_context
    failures = examples.filter_map do |example|
      result = Showcase::Playground::Runner.call(
        source: example.source,
        data_json: example.data_json.presence || "{}",
        view_context: view_context
      )
      next if result.success?

      "#{example.name || example.id}: #{result.diagnostics.first(2).map { |d| d['message'] }.join('; ')}"
    end

    assert_empty failures, "Playground examples no longer compile:\n#{failures.join("\n")}"
  end
end
