# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class IntermediateRepresentationTest < ActiveSupport::TestCase
      IR = IntermediateRepresentation

      test "wraps compiler output in immutable typed versioned nodes" do
        compilation = SourceCompiler.call(<<~RUBY)
          vstack do
            for_each(data[:items], id: "id") do |item|
              text(item[:name])
            end
          end
        RUBY

        assert_empty compilation.diagnostics
        document = IR.wrap(compilation.program, language_version: LanguageCatalog::VERSION)

        assert_equal IR::SCHEMA, document.schema
        assert_equal IR::VERSION, document.version
        assert_equal LanguageCatalog::VERSION, document.language_version
        assert_instance_of IR::View, document.root
        assert_instance_of IR::ForEach, document.root.children.first
        assert_instance_of IR::Expression, document.root.children.first.identity
        assert document.frozen?
        assert document.root.frozen?
        assert document.root.children.frozen?
        assert_raises(FrozenError) { document.root.children << document.root }
        assert_raises(FrozenError) { document.program.fetch("name").replace("changed") }
      end

      test "canonical serialization is deterministic and supports a location-free semantic form" do
        first = {
          type: "view",
          name: "text",
          arguments: [ { value: "Hello", type: "literal", location: location(1) } ],
          keywords: {},
          modifiers: [],
          children: [],
          location: location(1)
        }
        second = {
          "children" => [],
          "modifiers" => [],
          "location" => location(1),
          "keywords" => {},
          "arguments" => [ { "location" => location(1), "type" => "literal", "value" => "Hello" } ],
          "name" => "text",
          "type" => "view"
        }

        first_document = IR.wrap(first)
        second_document = IR.wrap(second)

        assert_equal first_document.canonical_json, second_document.canonical_json
        assert_equal first_document.canonical_json, IR::Document.from_json(first_document.canonical_json).canonical_json
        assert_includes first_document.canonical_json, '"schema":"swift-ui-rails.playground-ir"'
        assert_includes first_document.canonical_json, '"version":1'
        refute_includes first_document.semantic_json, '"location"'
      end

      test "rejects cycles and non JSON values before they become durable IR" do
        cyclic = []
        cyclic << cyclic

        error = assert_raises(IR::InvalidValue) { IR.wrap(cyclic) }
        assert_match(/cycles/i, error.message)

        error = assert_raises(IR::InvalidValue) { IR.wrap({ type: "view", name: Object.new }) }
        assert_match(/JSON-native/i, error.message)
        assert_equal "$.name", error.path
      end

      test "document construction defensively normalizes mutable caller input" do
        attributes = {
          "schema" => IR::SCHEMA,
          "version" => IR::VERSION,
          "language_version" => LanguageCatalog::VERSION,
          "root" => {
            "type" => "view",
            "name" => "text",
            "arguments" => [ { "type" => "literal", "value" => "Safe" } ],
            "keywords" => {},
            "modifiers" => [],
            "children" => []
          }
        }
        document = IR::Document.new(attributes)

        attributes["version"] = 999
        attributes.fetch("root")["name"] = "script"

        assert_equal IR::VERSION, document.version
        assert_equal IR::VERSION, document.to_h.fetch("version")
        assert_equal "text", document.root.name
        assert_predicate document.to_h, :frozen?
        assert_raises(FrozenError) { document.to_h["version"] = 999 }
      end

      private

      def location(line)
        { "line" => line, "column" => 1, "end_line" => line, "end_column" => 8 }
      end
    end
  end
end
