# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class AssistantSessionTest < ActiveSupport::TestCase
      class SequenceGenerator
        attr_reader :requests

        def initialize(*outputs)
          @outputs = outputs
          @requests = []
        end

        def call(**request)
          @requests << request
          @outputs.fetch(@requests.length - 1)
        end
      end

      setup do
        @view_context = ApplicationController.new.view_context
      end

      test "generates validates repairs and returns canonical DSL" do
        generator = SequenceGenerator.new(
          'text("Save").button_style(:bordered)',
          'button("Save").button_style(:bordered)'
        )

        session = AssistantSession.call(
          instruction: "Build a bordered Save button",
          data_json: "{ \"unused\": true }",
          view_context: @view_context,
          generator: generator
        )

        assert session.success?, session.diagnostics.inspect
        assert_equal 2, session.attempts
        assert_equal "button(\"Save\")\n  .button_style(:bordered)\n", session.source
        assert_equal 2, generator.requests.length
        initial_payload = JSON.parse(generator.requests.first.fetch(:messages).last.fetch(:content))
        assert_equal({ "unused" => true }, initial_payload.fetch("fixture"))
        refute initial_payload.key?("fixture_json")
        repair_payload = JSON.parse(generator.requests.last.fetch(:messages).last.fetch(:content))
        assert_equal true, repair_payload.fetch("repair")
        modifier_diagnostic = repair_payload.fetch("diagnostics").find { |diagnostic| diagnostic.fetch("code") == "modifier_incompatible" }
        assert_equal "$.root.modifiers[0]", modifier_diagnostic.fetch("path")
        assert_equal "remove", modifier_diagnostic.dig("fix", "kind")
        assert modifier_diagnostic.fetch("hint").present?
        assert_equal "dsl_source_only", generator.requests.first.dig(:response, :contract)
      end

      test "returns bounded diagnostics when no adapter is configured" do
        session = AssistantSession.call(
          instruction: "Build a view",
          data_json: "{}",
          view_context: @view_context,
          generator: nil
        )

        refute session.success?
        assert_equal 0, session.attempts
        assert_equal "assistant_unavailable", session.diagnostics.first.fetch(:code)
      end

      test "stops after the deterministic repair budget" do
        generator = SequenceGenerator.new(*Array.new(AssistantSession::MAX_ATTEMPTS, 'system("id")'))

        session = AssistantSession.call(
          instruction: "Build anything",
          data_json: "{}",
          view_context: @view_context,
          generator: generator
        )

        refute session.success?
        assert_equal AssistantSession::MAX_ATTEMPTS, session.attempts
        assert_equal AssistantSession::MAX_ATTEMPTS, generator.requests.length
        assert_includes session.diagnostics.map { |diagnostic| diagnostic.fetch("code") }, "unknown_view"
      end
    end
  end
end
