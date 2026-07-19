# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class ArtifactTest < ActiveSupport::TestCase
      setup do
        @source = "vstack { text(data[:title]).text_style(:headline) }\n"
        @data = { "title" => "Release" }.freeze
        @view_context = ApplicationController.new.view_context
        @compilation = SourceCompiler.call(@source)
        assert_empty @compilation.diagnostics
      end

      test "exports canonical source fixture versions and executable semantic expectations" do
        artifact = Artifact.build(source: @source, data: @data, ir: @compilation.program)
        document = artifact.to_h

        assert_equal Artifact::SCHEMA, document.fetch("schema")
        assert_equal Artifact::VERSION, document.fetch("version")
        assert_equal LanguageCatalog::VERSION, document.dig("language", "version")
        assert_equal IntermediateRepresentation::SCHEMA, document.dig("language", "ir_schema")
        assert_equal IntermediateRepresentation::VERSION, document.dig("language", "ir_version")
        refute document.fetch("language").key?("assistant_fingerprint")
        assert_equal @source, document.fetch("source")
        assert_equal @data, document.fetch("fixture")
        assert_match(/\A[0-9a-f]{64}\z/, document.dig("tests", "semantic_ir_sha256"))
        assert_match(/\A[0-9a-f]{64}\z/, artifact.fingerprint)
        assert_predicate document, :frozen?
      end

      test "verifies an unchanged artifact and rejects semantic drift" do
        artifact = Artifact.build(source: @source, data: @data, ir: @compilation.program)

        verification = ArtifactVerifier.call(artifact.to_json)
        assert verification.success?, verification.diagnostics.inspect
        assert_equal SourceFormatter.call(@source).source, verification.canonical_source

        rendered_verification = ArtifactVerifier.call(artifact.to_json, view_context: @view_context)
        assert rendered_verification.success?, rendered_verification.diagnostics.inspect

        changed = JSON.parse(artifact.to_json)
        changed["source"] = 'text("Different")'
        rejected = ArtifactVerifier.call(changed)

        refute rejected.success?
        assert_equal [ "artifact_semantics" ], rejected.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
      end

      test "rejects malformed and version-mismatched artifacts with domain diagnostics" do
        malformed = ArtifactVerifier.call("{broken")
        refute malformed.success?
        assert_equal "artifact_syntax", malformed.diagnostics.first.fetch(:code)

        wrong_version = ArtifactVerifier.call({
          "schema" => Artifact::SCHEMA,
          "version" => 99,
          "language" => { "version" => LanguageCatalog::VERSION }
        })
        refute wrong_version.success?
        assert_equal "artifact_version", wrong_version.diagnostics.first.fetch(:code)
      end

      test "rejects duplicate keys in serialized durable artifacts" do
        artifact = Artifact.build(source: @source, data: @data, ir: @compilation.program).to_json
        duplicated = artifact.sub('"title": "Release"', '"title": "First", "title": "Second"')

        result = ArtifactVerifier.call(duplicated)

        refute result.success?
        assert_equal "artifact_duplicate_key", result.diagnostics.first.fetch(:code)
        assert_equal "$.fixture.title", result.diagnostics.first.fetch(:path)
      end

      test "rejects altered verification expectations and security profiles" do
        artifact = Artifact.build(source: @source, data: @data, ir: @compilation.program)

        changed_compile = JSON.parse(artifact.to_json)
        changed_compile.fetch("tests")["compile"] = "failure"
        compile_rejection = ArtifactVerifier.call(changed_compile)
        refute compile_rejection.success?
        assert_equal "artifact_test_contract", compile_rejection.diagnostics.first.fetch(:code)

        changed_accessibility = JSON.parse(artifact.to_json)
        changed_accessibility.fetch("tests")["accessibility"] = "scanner_passed"
        accessibility_rejection = ArtifactVerifier.call(changed_accessibility)
        refute accessibility_rejection.success?
        assert_equal "artifact_test_contract", accessibility_rejection.diagnostics.first.fetch(:code)

        changed_security = JSON.parse(artifact.to_json)
        changed_security.fetch("tests")["security_profile"] = "trusted_ruby"
        security_rejection = ArtifactVerifier.call(changed_security)
        refute security_rejection.success?
        assert_equal "artifact_security_profile", security_rejection.diagnostics.first.fetch(:code)
        assert_equal "$.tests.security_profile", security_rejection.diagnostics.first.fetch(:path)

        additional_expectation = JSON.parse(artifact.to_json)
        additional_expectation.fetch("tests")["execute_prompt"] = true
        shape_rejection = ArtifactVerifier.call(additional_expectation)
        refute shape_rejection.success?
        assert_equal "artifact_tests", shape_rejection.diagnostics.first.fetch(:code)
      end

      test "rejects incomplete or drifted language contract metadata" do
        artifact = JSON.parse(
          Artifact.build(source: @source, data: @data, ir: @compilation.program).to_json
        )

        incomplete = artifact.deep_dup
        incomplete.fetch("language").delete("catalog_schema_version")
        incomplete_result = ArtifactVerifier.call(incomplete)
        refute incomplete_result.success?
        assert_equal "artifact_language", incomplete_result.diagnostics.first.fetch(:code)
        assert_equal "$.language", incomplete_result.diagnostics.first.fetch(:path)

        drifted = artifact.deep_dup
        drifted.fetch("language")["ir_version"] = 999
        drifted_result = ArtifactVerifier.call(drifted)
        refute drifted_result.success?
        assert_equal "artifact_language", drifted_result.diagnostics.first.fetch(:code)
        assert_equal "$.language.ir_version", drifted_result.diagnostics.first.fetch(:path)
      end

      test "parses the stored fixture through the bounded fixture contract" do
        artifact = JSON.parse(
          Artifact.build(source: @source, data: @data, ir: @compilation.program).to_json
        )
        artifact.fetch("fixture")["oversized_number"] = FixtureParser::MAX_NUMBER_MAGNITUDE + 1

        verification = ArtifactVerifier.call(artifact)

        refute verification.success?
        assert_equal [ "data_number" ], verification.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
        assert_equal "$.oversized_number", verification.diagnostics.first.fetch(:path)
      end

      test "optionally renders fixture data and rejects runtime identity errors" do
        source = <<~'RUBY'
          vstack do
            for_each(data[:tasks], id: "id") do |task|
              text(task[:title])
            end
          end
        RUBY
        data = {
          "tasks" => [
            { "id" => "duplicate", "title" => "First" },
            { "id" => "duplicate", "title" => "Second" }
          ]
        }
        compilation = SourceCompiler.call(source)
        assert_empty compilation.diagnostics
        artifact = Artifact.build(source: source, data: data, ir: compilation.program)

        compile_only = ArtifactVerifier.call(artifact.to_h)
        assert compile_only.success?, compile_only.diagnostics.inspect

        runtime = ArtifactVerifier.call(artifact.to_h, view_context: @view_context)
        refute runtime.success?
        assert_equal [ "duplicate_id" ], runtime.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
        assert_nil runtime.canonical_source
      end

      test "runtime verification rejects fixture drift that removes a control's accessible name" do
        source = "button(data[:label])"
        compilation = SourceCompiler.call(source)
        artifact = JSON.parse(
          Artifact.build(source: source, data: { "label" => "Save" }, ir: compilation.program).to_json
        )
        artifact.fetch("fixture")["label"] = "  "

        compile_only = ArtifactVerifier.call(artifact)
        runtime = ArtifactVerifier.call(artifact, view_context: @view_context)

        assert compile_only.success?, compile_only.diagnostics.inspect
        refute runtime.success?
        assert_equal [ "label_required" ], runtime.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
      end
    end
  end
end
