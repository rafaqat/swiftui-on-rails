# frozen_string_literal: true

require "digest"
require "json"

module Showcase
  module Playground
    # The complete, machine-readable contract supplied to a code-generating
    # assistant. The vocabulary is embedded from LanguageCatalog, keeping editor
    # help, validation, and model context on the same versioned source of truth.
    class AssistantContract
      CONTRACT_VERSION = "1.2.0"

      class << self
        def to_h(catalog: LanguageCatalog)
          return (@default_contract ||= new(catalog: catalog).to_h) if catalog.equal?(LanguageCatalog)

          new(catalog: catalog).to_h
        end

        def prompt_context(catalog: LanguageCatalog)
          return (@default_prompt_context ||= JSON.generate(to_h(catalog: catalog)).freeze) if catalog.equal?(LanguageCatalog)

          JSON.generate(to_h(catalog: catalog))
        end

        def fingerprint(catalog: LanguageCatalog)
          return (@default_fingerprint ||= Digest::SHA256.hexdigest(prompt_context(catalog: catalog)).freeze) if catalog.equal?(LanguageCatalog)

          Digest::SHA256.hexdigest(prompt_context(catalog: catalog))
        end
      end

      def initialize(catalog:)
        @catalog = catalog
      end

      def to_h
        @to_h ||= deep_freeze(
          {
            "contract_version" => CONTRACT_VERSION,
            "language" => {
              "id" => "swift_ui_rails_playground",
              "version" => catalog_version,
              "syntax" => "restricted_ruby_dsl",
              "trust_boundary" => "untrusted_source"
            },
            "objective" => [ "correctness", "semantic_intent", "accessibility", "security", "token_efficiency" ],
            "response" => {
              "content" => "dsl_source_only",
              "root_views" => 1,
              "markdown_fence" => false,
              "explanation" => false
            },
            "constraints" => [
              {
                "code" => "catalog_only",
                "rule" => "Use only builders, modifiers, statements, expressions, arguments, and enum values declared by catalog."
              },
              {
                "code" => "semantic_first",
                "rule" => "Prefer semantic vocabulary and semantic roles over low-level presentation escape hatches."
              },
              {
                "code" => "fixture_only",
                "rule" => "Read dynamic values only from data or the current for_each variable."
              },
              {
                "code" => "stable_identity",
                "rule" => "Every for_each must declare id using a unique stable key in each fixture item."
              },
              {
                "code" => "valid_composition",
                "rule" => "Respect block contracts, legal parents, argument types, and security constraints from catalog."
              },
              {
                "code" => "no_execution",
                "rule" => "Do not use arbitrary Ruby, constants, assignment, eval, file, process, network, or reflection APIs."
              },
              {
                "code" => "one_cognitive_model",
                "rule" => "Express all application state and behavior with catalogued DSL declarations that compile to RenderIR. Never generate JavaScript, Stimulus controllers, DOM queries or mutations, inline event handlers, data-controller, data-action, data-*-target, or event->controller#method strings. The framework-owned browser runtime is an allowlisted protocol interpreter, not an application programming surface."
              }
            ],
            "repair" => {
              "inputs" => [ "dsl_source", "fixture", "diagnostics" ],
              "preserve" => [ "user_intent", "valid_source", "fixture_shape" ],
              "output" => "complete_replacement_dsl_source"
            },
            "catalog" => generation_catalog
          }
        )
      end

      private

      def catalog_version
        @catalog.const_get(:VERSION).to_s
      end

      def generation_catalog
        return @catalog.for_generation if @catalog.respond_to?(:for_generation)

        @catalog.to_h
      end

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
