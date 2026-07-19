# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class SemanticValidatorTest < ActiveSupport::TestCase
      class RestrictedCatalog
        VERSION = LanguageCatalog::VERSION

        class << self
          delegate :builders, :modifiers, :statements, :expressions, :builder, to: LanguageCatalog

          def modifier(name)
            entry = LanguageCatalog.modifier(name)
            return entry unless name.to_s == "button_style"

            entry.merge("legal_targets" => [ "button" ])
          end
        end
      end

      test "accepts compiler output and returns a versioned document" do
        compilation = SourceCompiler.call(<<~RUBY)
          vstack(alignment: :leading) do
            text("Products").text_style(:title)
            for_each(data[:products], id: "id") do |product|
              text(product[:name]).foreground_style(:primary)
            end
          end
        RUBY

        result = SemanticValidator.call(compilation.program)

        assert result.success?, result.diagnostics.inspect
        assert_empty result.diagnostics
        assert_equal IntermediateRepresentation::VERSION, result.document.version
        assert_equal LanguageCatalog::VERSION, result.document.language_version
        assert_equal compilation.program.program, result.program
      end

      test "uses the language catalog as the expression operator source of truth" do
        assert_equal LanguageCatalog.expressions.dig("boolean", "operators"), SemanticValidator::BOOLEAN_OPERATORS
        assert_equal LanguageCatalog.expressions.dig("binary", "operators"), SemanticValidator::BINARY_OPERATORS
        assert_equal LanguageCatalog.expressions.dig("operation", "operators"), SemanticValidator::READ_OPERATIONS
      end

      test "rejects unsupported schema versions with a machine applicable fix" do
        document = IntermediateRepresentation.wrap(valid_text_program).to_h.merge("version" => 99)
        result = SemanticValidator.call(document)
        diagnostic = result.diagnostics.find { |item| item.fetch(:code) == "ir_version" }

        refute result.success?
        assert diagnostic
        assert_equal "$.version", diagnostic.fetch(:path)
        assert_equal "replace", diagnostic.dig(:fix, :kind)
        assert_equal IntermediateRepresentation::VERSION, diagnostic.dig(:fix, :value)
      end

      test "requires an explicit language version on persisted IR envelopes" do
        document = SourceCompiler.call('text("Versioned")').program.to_h.deep_dup
        document.delete("language_version")

        result = SemanticValidator.call(document)
        diagnostic = diagnostic_for(result, "language_version_missing")

        refute result.success?
        assert_equal "$.language_version", diagnostic.fetch(:path)
        assert_equal "add", diagnostic.dig(:fix, :kind)
        assert_equal LanguageCatalog::VERSION, diagnostic.dig(:fix, :value)
      end

      test "reports illegal children and unknown node types at stable IR paths" do
        program = deep_copy(valid_text_program)
        program["children"] << { "type" => "script", "location" => location(4) }

        result = SemanticValidator.call(program)

        assert_includes diagnostic_codes(result), "leaf_children"
        assert_includes diagnostic_codes(result), "node_type"
        diagnostic = result.diagnostics.find { |item| item.fetch(:code) == "node_type" }
        assert_equal "$.root.children[0].type", diagnostic.fetch(:path)
        assert_equal 4, diagnostic.fetch(:line)
        assert_match(/view, if, unless, for_each/, diagnostic.fetch(:hint))
        leaf = diagnostic_for(result, "leaf_children")
        assert_equal "replace", leaf.dig(:fix, :kind)
        assert_equal [], leaf.dig(:fix, :value)
      end

      test "checks modifier compatibility declared by the language catalog" do
        compilation = SourceCompiler.call('text("Save").button_style(:bordered)')
        result = SemanticValidator.call(compilation.program, catalog: RestrictedCatalog)
        diagnostic = result.diagnostics.find { |item| item.fetch(:code) == "modifier_incompatible" }

        refute result.success?
        assert diagnostic
        assert_equal "$.root.modifiers[0]", diagnostic.fetch(:path)
        assert_equal "remove", diagnostic.dig(:fix, :kind)
        assert_match(/cannot modify `text`/, diagnostic.fetch(:message))
      end

      test "rejects static modifier and positional enum values before rendering" do
        style_result = validate_source('text("Title").text_style(:marketing)')
        style_diagnostic = diagnostic_for(style_result, "text_style_value")

        refute style_result.success?
        assert_equal "$.root.modifiers[0].arguments[0]", style_diagnostic.fetch(:path)
        assert_match(/title|headline|supporting/, style_diagnostic.fetch(:hint))
        assert_equal "replace", style_diagnostic.dig(:fix, :kind)
        assert_includes LanguageCatalog.types.dig("text_style", "values"), style_diagnostic.dig(:fix, :value, "value")

        icon_result = validate_source("icon(:spaceship)")
        icon_diagnostic = diagnostic_for(icon_result, "icon_name_value")

        refute icon_result.success?
        assert_equal "$.root.arguments[0]", icon_diagnostic.fetch(:path)
        assert_equal "replace", icon_diagnostic.dig(:fix, :kind)
        assert_match(/search|star|check/, icon_diagnostic.fetch(:hint))
      end

      test "rejects bounded builder keyword literals with catalogue range fixes" do
        result = validate_source(<<~RUBY)
          grid(columns: 0, spacing: 99) do
            text("Outside bounds")
          end
        RUBY

        refute result.success?
        columns = diagnostic_for(result, "columns_range")
        spacing = diagnostic_for(result, "spacing_range")
        assert_equal "$.root.keywords.columns", columns.fetch(:path)
        assert_equal "$.root.keywords.spacing", spacing.fetch(:path)
        assert_match(/from 1 through 6/, columns.fetch(:message))
        assert_match(/from 0 through 32/, spacing.fetch(:message))
        assert_equal "replace", columns.dig(:fix, :kind)
        assert_includes 1..6, columns.dig(:fix, :value, "value")
        assert_includes 0..32, spacing.dig(:fix, :value, "value")
      end

      test "enforces primitive boolean number and integer literal types" do
        integer_result = validate_source("grid(columns: 2.5) { text(\"Grid\") }")
        boolean_result = validate_source('button("Save", disabled: "yes")')
        number_result = validate_source('gauge(value: "full", label: "Capacity")')

        integer = diagnostic_for(integer_result, "columns_type")
        boolean = diagnostic_for(boolean_result, "disabled_type")
        number = diagnostic_for(number_result, "value_type")
        assert_equal "$.root.keywords.columns", integer.fetch(:path)
        assert_match(/integer/, integer.fetch(:message))
        assert_equal "$.root.keywords.disabled", boolean.fetch(:path)
        assert_match(/true or false/, boolean.fetch(:message))
        assert_equal false, boolean.dig(:fix, :value, "value")
        assert_equal "$.root.keywords.value", number.fetch(:path)
        assert_match(/finite number/, number.fetch(:message))
        [ integer, boolean, number ].each do |diagnostic|
          assert diagnostic.fetch(:hint).present?
          assert_equal "replace", diagnostic.dig(:fix, :kind)
        end
      end

      test "rejects statically empty accessible control labels with a repair" do
        {
          'button("  ")' => [ "$.root.arguments[0]", "Action" ],
          'progress_view(label: "")' => [ "$.root.keywords.label", "Progress" ],
          'gauge(value: 50, label: "\n")' => [ "$.root.keywords.label", "Value" ]
        }.each do |source, (path, replacement)|
          result = validate_source(source)
          diagnostic = diagnostic_for(result, "label_required")

          refute result.success?
          assert_equal path, diagnostic.fetch(:path)
          assert_match(/accessible name/, diagnostic.fetch(:message))
          assert_match(/visible label/, diagnostic.fetch(:hint))
          assert_equal({ "type" => "literal", "value" => replacement }, diagnostic.dig(:fix, :value))
        end
      end

      test "rejects invalid patterned colors with domain fixes" do
        color_result = validate_source('text("Alert").text_color("red-999")')
        color = diagnostic_for(color_result, "color_value")

        refute color_result.success?
        assert_equal "$.root.modifiers[0].arguments[0]", color.fetch(:path)
        assert_match(/slate-600|semantic/, color.fetch(:hint))
        assert_equal "replace", color.dig(:fix, :kind)
        assert_equal "white", color.dig(:fix, :value, "value")
      end

      test "rejects size-only spacing tokens and impossible special-color shades" do
        spacing_result = validate_source('text("Notice").padding("auto")')
        color_result = validate_source('text("Notice").text_color("transparent-500")')

        spacing = diagnostic_for(spacing_result, "spacing_value")
        color = diagnostic_for(color_result, "color_value")
        refute spacing_result.success?
        refute color_result.success?
        assert_equal "$.root.modifiers[0].arguments[0]", spacing.fetch(:path)
        assert_match(/one of/i, spacing.fetch(:hint))
        assert_equal "$.root.modifiers[0].arguments[0]", color.fetch(:path)
        assert_match(/allowlisted|semantic/i, color.fetch(:hint))
      end

      test "defers fixture and loop-derived argument values to bounded runtime checks" do
        result = validate_source(<<~RUBY)
          vstack(spacing: data[:stack_spacing]) do
            grid(columns: data[:columns], spacing: data[:grid_spacing]) do
              button(
                data[:label],
                disabled: data[:disabled]
              )
                .button_style(data[:button_style])
                .bg(data[:button_color])
            end

            for_each(data[:items], id: "id") do |item|
              text(item[:label])
                .text_style(item[:text_style])
                .text_color(item[:color])
            end
          end
        RUBY

        assert result.success?, result.diagnostics.inspect
        assert_empty result.diagnostics
      end

      test "requires a literal safe stable identity for every for_each" do
        missing = deep_copy(valid_for_each_program)
        missing.delete("id")
        missing_result = SemanticValidator.call(missing)
        missing_diagnostic = missing_result.diagnostics.find { |item| item.fetch(:code) == "for_each_identity_missing" }

        assert missing_diagnostic
        assert_equal "add", missing_diagnostic.dig(:fix, :kind)
        assert_equal "id", missing_diagnostic.dig(:fix, :value, "value")

        dynamic = deep_copy(valid_for_each_program)
        dynamic["id"] = variable_expression("identity_key", line: 1)
        dynamic_result = SemanticValidator.call(dynamic)

        assert_includes diagnostic_codes(dynamic_result), "for_each_identity_literal"
        assert_includes diagnostic_codes(dynamic_result), "unknown_variable"

        unsafe = deep_copy(valid_for_each_program)
        unsafe["id"] = literal_expression("9 bad key", line: 1)
        unsafe_result = SemanticValidator.call(unsafe)

        assert_includes diagnostic_codes(unsafe_result), "for_each_identity_key"
      end

      private

      def valid_text_program
        {
          "type" => "view",
          "name" => "text",
          "arguments" => [ literal_expression("Hello", line: 1) ],
          "keywords" => {},
          "modifiers" => [],
          "children" => [],
          "location" => location(1)
        }
      end

      def valid_for_each_program
        {
          "type" => "for_each",
          "collection" => {
            "type" => "index",
            "receiver" => variable_expression("data", line: 1),
            "key" => { "type" => "symbol", "value" => "items", "location" => location(1) },
            "location" => location(1)
          },
          "id" => literal_expression("id", line: 1),
          "variable" => "item",
          "children" => [ valid_text_program ],
          "location" => location(1)
        }
      end

      def literal_expression(value, line:)
        { "type" => "literal", "value" => value, "location" => location(line) }
      end

      def variable_expression(name, line:)
        { "type" => "variable", "name" => name, "location" => location(line) }
      end

      def location(line)
        { "line" => line, "column" => 1, "end_line" => line, "end_column" => 8 }
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def validate_source(source)
        compilation = SourceCompiler.call(source)
        assert_empty compilation.diagnostics, compilation.diagnostics.inspect

        SemanticValidator.call(compilation.program)
      end

      def diagnostic_for(result, code)
        result.diagnostics.find { |diagnostic| diagnostic.fetch(:code) == code } ||
          flunk("Expected #{code.inspect}; got #{result.diagnostics.inspect}")
      end

      def diagnostic_codes(result)
        result.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
      end
    end
  end
end
