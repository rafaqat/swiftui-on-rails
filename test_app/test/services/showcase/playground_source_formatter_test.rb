# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class SourceFormatterTest < ActiveSupport::TestCase
      test "formats valid source through compiler IR and is idempotent" do
        input = <<~'RUBY'
          vstack(spacing:8){text("Hello #{data[:name]}").text_style(:headline);if data[:ready];badge("Ready",tone: :success);else;badge("Hold",tone: :warning);end}
        RUBY

        first = SourceFormatter.call(input)
        second = SourceFormatter.call(first.source)

        assert first.success?, first.diagnostics.inspect
        assert first.changed
        assert second.success?, second.diagnostics.inspect
        assert_not second.changed
        assert_equal first.source, second.source
        assert_equal <<~'RUBY', first.source
          vstack(spacing: 8) do
            text("Hello #{data[:name]}")
              .text_style(:headline)
            if data[:ready]
              badge("Ready", tone: :success)
            else
              badge("Hold", tone: :warning)
            end
          end
        RUBY
      end

      test "preserves the compiled semantics while discarding source locations" do
        input = <<~'RUBY'
          vstack do
            for_each(data[:items], id: "id") do |item|
              unless item[:hidden] || item[:count] == 0
                text("#{item[:name]}: #{item[:count] + 1}").foreground_style(:primary)
              end
            end
          end
        RUBY

        formatted = SourceFormatter.call(input)
        original_program = SourceCompiler.call(input).program.program
        formatted_program = SourceCompiler.call(formatted.source).program.program

        assert formatted.success?, formatted.diagnostics.inspect
        assert_equal without_locations(original_program), without_locations(formatted_program)
      end

      test "returns compiler diagnostics and no replacement source for invalid input" do
        formatted = SourceFormatter.call("text(eval(data[:payload]))")

        assert_not formatted.success?
        assert_nil formatted.source
        assert_not formatted.changed
        assert_equal [ "unknown_expression" ], formatted.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
      end

      private

      def without_locations(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), copy|
            copy[key] = without_locations(child) unless key == "location"
          end
        when Array
          value.map { |child| without_locations(child) }
        else
          value
        end
      end
    end
  end
end
