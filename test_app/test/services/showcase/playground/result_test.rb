# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class ResultTest < ActiveSupport::TestCase
      test "exposes typed authoring and resolved IR documents as JSON data" do
        authoring_ir = IntermediateRepresentation.wrap(
          {
            type: "view",
            name: "text",
            arguments: [ { type: "literal", value: "Hello" } ],
            keywords: {},
            modifiers: [],
            children: []
          },
          language_version: LanguageCatalog::VERSION
        )
        render_ir = SwiftUIRails::RenderIR::Document.new(
          root: SwiftUIRails::RenderIR::Node.new(
            kind: "text",
            props: { content: "Hello" },
            accessibility: { role: "text" }
          ),
          profile: "playground",
          language_version: LanguageCatalog::VERSION
        )
        result = Result.new(
          html: "<span>Hello</span>",
          diagnostics: [],
          stats: {},
          data: {},
          ir: authoring_ir,
          render_ir: render_ir
        )

        payload = result.as_json

        assert_same render_ir, result.render_ir
        assert_equal authoring_ir.to_h, payload.fetch(:authoring_ir)
        assert_equal render_ir.to_h, payload.fetch(:render_ir)
        assert_equal SwiftUIRails::RenderIR::SCHEMA, payload.dig(:render_ir, "schema")
        assert_equal SwiftUIRails::RenderIR::VERSION, payload.dig(:render_ir, "version")
        assert_predicate payload.fetch(:render_ir), :frozen?
      end

      test "keeps render IR optional and rejects untyped lowering output" do
        result = Result.new(html: "", diagnostics: [], stats: {}, data: {})

        assert_nil result.render_ir
        assert_nil result.as_json.fetch(:render_ir)
        assert_nil result.as_json.fetch(:authoring_ir)

        error = assert_raises(TypeError) do
          Result.new(html: "", diagnostics: [], stats: {}, data: {}, render_ir: { "root" => {} })
        end
        assert_equal "render_ir must be a SwiftUIRails::RenderIR::Document", error.message
      end
    end
  end
end
