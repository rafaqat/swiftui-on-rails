# frozen_string_literal: true

require "json"

module Showcase
  module Playground
    # Provider-neutral generate -> validate -> repair coordinator. Applications
    # inject a callable model adapter; the session supplies the compact language
    # contract, accepts DSL source only, and feeds bounded domain diagnostics
    # back for repair. No prompt or generated source is evaluated as Ruby.
    class AssistantSession
      MAX_ATTEMPTS = 3
      INSTRUCTION_BYTES = 8.kilobytes

      SessionResult = Struct.new(:ok, :source, :result, :attempts, :diagnostics, keyword_init: true) do
        def success?
          ok
        end

        def as_json(*)
          {
            ok: ok,
            source: source,
            attempts: attempts,
            diagnostics: diagnostics,
            preview: result&.as_json
          }.compact
        end
      end

      def self.call(instruction:, data_json:, view_context:, generator:, current_source: nil)
        new(
          instruction: instruction,
          data_json: data_json,
          view_context: view_context,
          generator: generator,
          current_source: current_source
        ).call
      end

      def initialize(instruction:, data_json:, view_context:, generator:, current_source: nil)
        @instruction = instruction.to_s
        @data_json = data_json.to_s
        @view_context = view_context
        @generator = generator
        @current_source = current_source&.to_s
      end

      def call
        return failure("assistant_unavailable", "No language-model adapter is configured for this playground.") unless @generator.respond_to?(:call)
        return failure("assistant_instruction", "Describe the view you want the assistant to build.") if @instruction.strip.empty?
        return failure("assistant_instruction_size", "Assistant instructions are limited to #{INSTRUCTION_BYTES / 1024} KiB.") if @instruction.bytesize > INSTRUCTION_BYTES

        fixture = FixtureParser.call(@data_json)
        return SessionResult.new(ok: false, attempts: 0, diagnostics: fixture.diagnostics, result: nil).freeze if fixture.diagnostics.any?
        return failure("assistant_source_size", "Current DSL source is too large for an assistant request.") if @current_source&.bytesize.to_i > Limits::SOURCE_BYTES

        @fixture_context = fixture.data

        messages = initial_messages
        last_source = nil
        last_result = nil

        MAX_ATTEMPTS.times do |index|
          last_source = generate(messages)
          unless last_source.is_a?(String) && last_source.bytesize <= Limits::SOURCE_BYTES
            return failure("assistant_output", "The model adapter must return bounded DSL source as a string.", attempts: index + 1)
          end

          last_result = Runner.call(source: last_source, data_json: @data_json, view_context: @view_context)
          if last_result.success?
            return SessionResult.new(
              ok: true,
              source: last_result.canonical_source || last_source,
              result: last_result,
              attempts: index + 1,
              diagnostics: [].freeze
            ).freeze
          end

          messages = repair_messages(messages, last_source, last_result.diagnostics)
        end

        SessionResult.new(
          ok: false,
          source: last_source,
          result: last_result,
          attempts: MAX_ATTEMPTS,
          diagnostics: last_result&.diagnostics || [].freeze
        ).freeze
      rescue StandardError => error
        Rails.logger.info("[Playground] Assistant adapter failed: #{error.class}")
        failure("assistant_failure", "The assistant could not produce a safe view.")
      end

      private

      def initial_messages
        [
          { role: "system", content: AssistantContract.prompt_context },
          {
            role: "user",
            content: JSON.generate({
              instruction: @instruction,
              fixture: @fixture_context,
              current_dsl: @current_source
            }.compact)
          }
        ].freeze
      end

      def generate(messages)
        output = @generator.call(
          messages: messages,
          response: {
            type: "text",
            contract: "dsl_source_only",
            max_bytes: Limits::SOURCE_BYTES
          }.freeze
        )
        output.respond_to?(:source) ? output.source : output
      end

      def repair_messages(messages, source, diagnostics)
        concise = Array(diagnostics).first(Limits::DIAGNOSTICS).map do |diagnostic|
          normalized = diagnostic.respond_to?(:deep_stringify_keys) ? diagnostic.deep_stringify_keys : diagnostic
          {
            code: normalized["code"],
            line: normalized["line"],
            column: normalized["column"],
            path: normalized["path"],
            message: normalized["message"],
            hint: normalized["hint"],
            fix: compact_fix(normalized["fix"])
          }.compact
        end

        (messages + [
          { role: "assistant", content: source },
          {
            role: "user",
            content: JSON.generate({
              repair: true,
              diagnostics: concise,
              instruction: "Return one complete corrected DSL source document only."
            })
          }
        ]).freeze
      end

      def compact_fix(value)
        return unless value.is_a?(Hash)

        value.slice("kind", "path", "value")
      end

      def failure(code, message, attempts: 0)
        SessionResult.new(
          ok: false,
          source: nil,
          result: nil,
          attempts: attempts,
          diagnostics: [ {
            source: "assistant",
            severity: "error",
            code: code,
            message: message,
            line: 1,
            column: 1,
            end_line: 1,
            end_column: 1,
            path: nil
          }.freeze ].freeze
        ).freeze
      end
    end
  end
end
