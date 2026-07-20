# frozen_string_literal: true

require "digest"
require "json"

module Showcase
  module Playground
    # Re-runs an exported artifact's syntax and semantic checks without trusting
    # persisted IR or HTML. This keeps the checked-in DSL artifact authoritative.
    class ArtifactVerifier
      Verification = Struct.new(:ok, :diagnostics, :canonical_source, keyword_init: true) do
        def success?
          ok
        end

        def as_json(*)
          { ok: ok, diagnostics: diagnostics, canonical_source: canonical_source }.compact
        end
      end

      def self.call(value, view_context: nil)
        new(value, view_context: view_context).call
      end

      def initialize(value, view_context: nil)
        @value = value
        @view_context = view_context
      end

      def call
        # Scope the parse rescues to parsing only. A method-level rescue would
        # also swallow ArgumentError/TypeError raised inside the downstream
        # compiler/validator/renderer services, misreporting a real bug as an
        # "unsupported values" artifact failure.
        artifact = begin
          parse_artifact
        rescue JSON::ParserError, JSON::NestingError
          return failure("artifact_syntax", "The artifact is not valid bounded JSON.")
        rescue FixtureParser::DuplicateKeyError => error
          return failure("artifact_duplicate_key", "The artifact repeats the object key `#{error.key}`.", path: error.path)
        rescue JSON::GeneratorError, TypeError, ArgumentError
          return failure("artifact_shape", "The artifact contains unsupported values.")
        end
        return failure("artifact_schema", "This is not a SwiftUI Rails playground artifact.") unless artifact["schema"] == Artifact::SCHEMA
        return failure("artifact_version", "Artifact version `#{artifact['version'].inspect}` is not supported.") unless artifact["version"] == Artifact::VERSION

        language = artifact["language"]
        language_failure = validate_language_contract(language)
        return language_failure if language_failure

        source = artifact["source"]
        fixture = artifact["fixture"]
        tests = artifact["tests"]
        return failure("artifact_source", "The artifact must contain DSL source.") unless source.is_a?(String)
        return failure("artifact_fixture", "The artifact fixture must be a JSON object.") unless fixture.is_a?(Hash)
        return failure("artifact_tests", "The artifact must contain verification expectations.") unless tests.is_a?(Hash)
        contract_failure = validate_test_contract(tests)
        return contract_failure if contract_failure

        parsed_fixture = FixtureParser.call(JSON.generate(fixture))
        return rejected(parsed_fixture.diagnostics) if parsed_fixture.diagnostics.any?

        compilation = SourceCompiler.call(source)
        return rejected(compilation.diagnostics) if compilation.diagnostics.any?

        validation = SemanticValidator.call(compilation.program)
        return rejected(validation.diagnostics) unless validation.success?

        expected = tests["semantic_ir_sha256"]
        actual = Digest::SHA256.hexdigest(validation.document.semantic_json)
        return failure("artifact_semantics", "The compiled view no longer matches the artifact's semantic expectation.") unless secure_equal?(expected, actual)

        if @view_context
          rendering = Renderer.call(
            program: validation.document,
            data: parsed_fixture.data,
            view_context: @view_context
          )
          return rejected(rendering.diagnostics) if rendering.diagnostics.any?
        end

        formatted = SourceFormatter.call(source)
        return rejected(formatted.diagnostics) unless formatted.success?

        Verification.new(ok: true, diagnostics: [].freeze, canonical_source: formatted.source).freeze
      end

      private

      def parse_artifact
        return normalize(@value) if @value.is_a?(Hash)

        source = @value.to_s
        raise JSON::ParserError, "artifact too large" if source.bytesize > Limits::REQUEST_BYTES

        FixtureParser::DuplicateKeyScanner.call(source, max_depth: Limits::DATA_DEPTH + 4)
        normalize(JSON.parse(source, create_additions: false, max_nesting: Limits::DATA_DEPTH + 4))
      end

      def normalize(value)
        source = JSON.generate(value)
        raise JSON::ParserError, "artifact too large" if source.bytesize > Limits::REQUEST_BYTES

        JSON.parse(source, create_additions: false, max_nesting: Limits::DATA_DEPTH + 4)
      end

      def secure_equal?(expected, actual)
        expected.is_a?(String) && expected.bytesize == actual.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(expected, actual)
      end

      def validate_test_contract(tests)
        unless tests.keys.sort == Artifact::TEST_KEYS.sort
          return failure(
            "artifact_tests",
            "Artifact verification expectations must contain exactly #{Artifact::TEST_KEYS.join(', ')}.",
            path: "$.tests"
          )
        end

        unless tests["compile"] == Artifact::COMPILE_EXPECTATION
          return failure(
            "artifact_test_contract",
            "Artifact compile verification must require success.",
            path: "$.tests.compile"
          )
        end

        unless tests["accessibility"] == Artifact::ACCESSIBILITY_EXPECTATION
          return failure(
            "artifact_test_contract",
            "Artifact accessibility intent must require semantic HTML.",
            path: "$.tests.accessibility"
          )
        end

        unless tests["security_profile"] == LanguageCatalog::PROFILE
          return failure(
            "artifact_security_profile",
            "The artifact targets a different security profile.",
            path: "$.tests.security_profile"
          )
        end

        digest = tests["semantic_ir_sha256"]
        return if digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)

        failure(
          "artifact_test_contract",
          "The artifact semantic expectation must be a SHA-256 digest.",
          path: "$.tests.semantic_ir_sha256"
        )
      end

      def validate_language_contract(language)
        unless language.is_a?(Hash) && language.keys.sort == Artifact::LANGUAGE_KEYS.sort
          return failure(
            "artifact_language",
            "Artifact language metadata is incomplete or unsupported.",
            path: "$.language"
          )
        end

        expected = {
          "id" => LanguageCatalog.to_h.fetch("name"),
          "version" => LanguageCatalog::VERSION,
          "catalog_schema_version" => LanguageCatalog::SCHEMA_VERSION,
          "ir_schema" => IntermediateRepresentation::SCHEMA,
          "ir_version" => IntermediateRepresentation::VERSION
        }
        mismatch = expected.find { |key, value| language[key] != value }
        if mismatch
          return failure(
            "artifact_language",
            "The artifact targets a different #{mismatch.first.tr('_', ' ')}.",
            path: "$.language.#{mismatch.first}"
          )
        end

        nil
      end

      def rejected(diagnostics)
        bounded = Array(diagnostics).first(Limits::DIAGNOSTICS).map do |diagnostic|
          diagnostic.dup.freeze
        end.freeze
        Verification.new(ok: false, diagnostics: bounded, canonical_source: nil).freeze
      end

      def failure(code, message, path: "$")
        Verification.new(
          ok: false,
          canonical_source: nil,
          diagnostics: [ {
            source: "artifact",
            severity: "error",
            code: code,
            message: message,
            line: 1,
            column: 1,
            end_line: 1,
            end_column: 1,
            path: path
          }.freeze ].freeze
        ).freeze
      end
    end
  end
end
