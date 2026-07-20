# frozen_string_literal: true

require "digest"
require "json"

module Showcase
  module Playground
    # Durable, vendor-neutral output of the playground authoring loop. Prompts
    # are intentionally absent: the canonical DSL, fixture, language version,
    # semantic IR digest, and executable verification expectations are enough to
    # reproduce and check the authored view.
    class Artifact
      SCHEMA = "swift-ui-rails.playground-artifact"
      VERSION = 1
      COMPILE_EXPECTATION = "success"
      ACCESSIBILITY_EXPECTATION = "semantic_html_required"
      LANGUAGE_KEYS = %w[id version catalog_schema_version ir_schema ir_version].freeze
      TEST_KEYS = %w[compile semantic_ir_sha256 accessibility security_profile].freeze

      # Single source of truth for the artifact's language-contract block, so the
      # builder here and ArtifactVerifier's expectation can never drift apart.
      def self.language_metadata
        {
          "id" => LanguageCatalog.to_h.fetch("name"),
          "version" => LanguageCatalog::VERSION,
          "catalog_schema_version" => LanguageCatalog::SCHEMA_VERSION,
          "ir_schema" => IntermediateRepresentation::SCHEMA,
          "ir_version" => IntermediateRepresentation::VERSION
        }.freeze
      end

      attr_reader :document

      def self.build(source:, data:, ir:)
        new(source: source, data: data, ir: ir)
      end

      def initialize(source:, data:, ir:)
        ir_document = IntermediateRepresentation.wrap(
          ir,
          language_version: LanguageCatalog::VERSION
        )
        semantic_sha = Digest::SHA256.hexdigest(ir_document.semantic_json)
        source_text = source.to_s.dup.freeze
        fixture = IntermediateRepresentation::Normalizer.call(data, path: "$.fixture")

        @document = deep_freeze({
          "schema" => SCHEMA,
          "version" => VERSION,
          "language" => self.class.language_metadata,
          "source" => source_text,
          "fixture" => fixture,
          "tests" => {
            "compile" => COMPILE_EXPECTATION,
            "semantic_ir_sha256" => semantic_sha,
            "accessibility" => ACCESSIBILITY_EXPECTATION,
            "security_profile" => LanguageCatalog::PROFILE
          }
        })
        freeze
      end

      def to_h
        document
      end

      def as_json(*)
        to_h
      end

      def to_json(*)
        JSON.pretty_generate(document)
      end

      def fingerprint
        Digest::SHA256.hexdigest(JSON.generate(document))
      end

      private

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| key.freeze; deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        else
          value.freeze
        end
        value.freeze
      end
    end
  end
end
