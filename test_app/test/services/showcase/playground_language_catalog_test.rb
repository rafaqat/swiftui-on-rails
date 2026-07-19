# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class LanguageCatalogTest < ActiveSupport::TestCase
      test "publishes a deeply frozen JSON-native versioned document" do
        document = LanguageCatalog.to_h

        assert_equal "1.1.0", document.fetch("language_version")
        assert_equal 1, document.fetch("catalog_schema_version")
        assert_equal "browser_playground", document.fetch("profile")
        assert_equal document, JSON.parse(JSON.generate(document))
        assert_json_native_and_frozen(document)
      end

      test "enforces Ruby and RenderIR as the only application behavior model" do
        policy = LanguageCatalog.to_h.fetch("application_model")

        assert_equal "ruby_render_ir", policy.fetch("authority")
        assert_equal "server_owned", policy.fetch("state")
        assert_equal "catalogued_dsl_declarations", policy.fetch("behavior")
        assert_equal "framework_owned_allowlisted_protocol_interpreter", policy.fetch("browser_runtime")
        assert_equal false, policy.fetch("application_javascript")
        assert_equal false, policy.fetch("stimulus")
        assert_equal false, policy.fetch("controller_dispatch")
        assert_equal false, policy.fetch("arbitrary_browser_commands")
        assert_equal %w[data-controller data-action data-*-target event->controller#method],
                     policy.fetch("forbidden_dom_contracts")
        assert_equal %w[
          javascript_source stimulus_controller stimulus_action stimulus_target
          stimulus_param inline_event_handler dom_query dom_mutation
        ], policy.fetch("forbidden_authoring_surfaces")
        assert_equal policy, LanguageCatalog.for_generation.fetch("application_model")
      end

      test "compiler and semantic validation reject browser controller authoring" do
        {
          'button("Add").stimulus_controller("cart")' => "unknown_view",
          'button("Add", data_controller: "cart")' => "unknown_keyword",
          'button("Add", action: "inspect_product")' => "unknown_keyword",
          'script("alert(1)")' => "unknown_view"
        }.each do |source, expected_code|
          result = SourceCompiler.call(source)

          assert_nil result.program, source
          assert_equal [ expected_code ], result.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }, source
        end

        refute_includes LanguageCatalog.builder("button").dig("arguments", "keywords"), "action"
        refute_includes LanguageCatalog.types, "action_name"
      end

      test "is the executable source of truth for every runtime resource limit" do
        LanguageCatalog.to_h.fetch("limits").each do |name, value|
          constant = name.upcase

          assert Limits.const_defined?(constant, false), "missing runtime limit #{constant}"
          assert_equal value, Limits.const_get(constant, false), name
        end
      end

      test "catalogues every compiler builder with its exact call shape" do
        assert_equal SourceCompiler::BUILDERS.keys.sort, LanguageCatalog.builders.keys.sort

        SourceCompiler::BUILDERS.each do |name, compiler_schema|
          entry = LanguageCatalog.builder(name)
          arguments = entry.fetch("arguments")

          assert_equal compiler_schema.fetch(:positional), arguments.fetch("positional").length, name
          assert_equal compiler_schema.fetch(:keywords).sort, arguments.fetch("keywords").keys.sort, name
          assert_equal compiler_schema.fetch(:block) ? "required" : "forbidden", entry.dig("block", "mode"), name
          assert_equal "semantic", entry.fetch("tier"), name
          assert_includes entry.fetch("contexts"), "root", name
          assert_includes entry.fetch("legal_parents"), "$root", name
        end
      end

      test "catalogues every compiler modifier with its exact arity" do
        assert_equal SourceCompiler::MODIFIERS.keys.sort, LanguageCatalog.modifiers.keys.sort

        SourceCompiler::MODIFIERS.each do |name, compiler_arity|
          entry = LanguageCatalog.modifier(name)
          arity = entry.dig("arguments", "arity")
          expected_minimum, expected_maximum = if compiler_arity.is_a?(Range)
            [ compiler_arity.begin, compiler_arity.end ]
          else
            [ compiler_arity, compiler_arity ]
          end

          assert_equal expected_minimum, arity.fetch("minimum"), name
          assert_equal expected_maximum, arity.fetch("maximum"), name
          assert_operator entry.fetch("legal_targets").length, :>=, 1, name
          assert_includes %w[semantic escape_hatch], entry.fetch("tier"), name
        end
      end

      test "enum and patterned types match the fixed renderer contract" do
        expected_enums = {
          "alignment" => Renderer::ALIGNMENTS.keys,
          "stack_alignment" => Renderer::STACK_ALIGNMENTS.keys,
          "badge_tone" => Renderer::BADGE_TONES.keys,
          "button_style" => Renderer::BUTTON_STYLES.keys,
          "button_size" => Renderer::BUTTON_SIZES.keys,
          "text_size" => Renderer::TEXT_SIZES,
          "font_weight" => Renderer::FONT_WEIGHTS,
          "foreground_style" => Renderer::FOREGROUND_STYLES.keys,
          "background_style" => Renderer::BACKGROUND_STYLES.keys,
          "font" => Renderer::FONTS.keys,
          "text_style" => Renderer::TEXT_STYLES.keys,
          "corner_radius" => Renderer::ROUNDED,
          "shadow" => Renderer::SHADOWS,
          "opacity" => Renderer::OPACITIES,
          "spacing" => Renderer::SPACING,
          "size" => Renderer::SIZES,
          "max_size" => Renderer::MAX_SIZES,
          "icon_name" => SwiftUIRails::DSL::ICON_GLYPHS.keys
        }

        expected_enums.each do |type, values|
          assert_equal values.sort, LanguageCatalog.types.fetch(type).fetch("values").sort, type
        end

        color_forms = LanguageCatalog.types.fetch("safe_color").fetch("forms")
        assert_equal Renderer::COLOR_NAMES.sort, color_forms.first.fetch("name_values").sort
        assert_equal Renderer::SHADEABLE_COLOR_NAMES.sort, color_forms.last.fetch("name_values").sort
        assert_equal Renderer::COLOR_SHADES.sort, color_forms.last.fetch("shade_values").sort
        assert_empty color_forms.first.fetch("name_values") & color_forms.last.fetch("name_values")
        refute_includes color_forms.first.fetch("name_values"), "red"
        assert_empty LanguageCatalog.types.fetch("spacing").fetch("values") & %w[auto full 1/2 1/3]
        assert_includes LanguageCatalog.types.fetch("size").fetch("values"), "auto"
        refute_includes LanguageCatalog.types.fetch("max_size").fetch("values"), "auto"
      end

      test "every finite Tailwind utility has a compiled CSS selector" do
        css = Rails.root.join("app/assets/builds/tailwind.css").read
        utilities = LanguageCatalog.tailwind_utility_classes
        missing = utilities.reject do |utility|
          escaped = utility.each_char.map { |character| %w[. /].include?(character) ? "\\#{character}" : character }.join
          css.match?(/#{Regexp.escape(".#{escaped}")}\s*\{/)
        end

        assert_predicate utilities, :frozen?
        assert_equal utilities.uniq.sort, utilities
        assert_empty missing, "catalogued utilities missing from compiled Tailwind CSS: #{missing.join(', ')}"
      end

      test "all argument type references resolve and availability is explicit" do
        entries = LanguageCatalog.builders.values + LanguageCatalog.modifiers.values + LanguageCatalog.statements.values

        entries.each do |entry|
          assert_equal LanguageCatalog::INITIAL_VERSION, entry.dig("availability", "since")
          assert_includes entry.dig("availability", "profiles"), LanguageCatalog::PROFILE
          assert_kind_of Array, entry.fetch("security")

          argument_definitions(entry).each do |argument|
            assert LanguageCatalog.types.key?(argument.fetch("type")), "unknown type #{argument.fetch('type')}"
          end
        end
      end

      test "marks semantic authoring APIs separately from low-level escape hatches" do
        %w[padding foreground_style background_style font text_style hidden disabled button_style button_size].each do |name|
          assert_equal "semantic", LanguageCatalog.modifier(name).fetch("tier"), name
        end

        %w[p px py m mx my bg text_color text_size font_weight rounded shadow border border_color opacity w h w_full].each do |name|
          assert_equal "escape_hatch", LanguageCatalog.modifier(name).fetch("tier"), name
        end

        assert_match(/prefer background_style/i, LanguageCatalog.modifier("bg").fetch("security").join(" "))
        assert_match(/prefer foreground_style/i, LanguageCatalog.modifier("text_color").fetch("security").join(" "))
        assert_equal [ "button" ], LanguageCatalog.modifier("button_style").fetch("legal_targets")
        assert_equal [ "button" ], LanguageCatalog.modifier("button_size").fetch("legal_targets")
        assert_equal [ "button" ], LanguageCatalog.modifier("disabled").fetch("legal_targets")
      end

      test "publishes a smaller semantic-only generation contract" do
        contract = LanguageCatalog.for_generation

        assert_equal LanguageCatalog::VERSION, contract.fetch("language_version")
        assert_equal "ruby_render_ir", contract.dig("application_model", "authority")
        assert_equal false, contract.dig("application_model", "application_javascript")
        assert_equal LanguageCatalog.builders.keys.sort, contract.fetch("builders").keys.sort
        assert_includes contract.fetch("modifiers"), "text_style"
        refute_includes contract.fetch("modifiers"), "text_color"
        refute_includes contract.fetch("modifiers"), "bg"
        assert_operator JSON.generate(contract).bytesize, :<, JSON.generate(LanguageCatalog.to_h).bytesize
        assert_predicate contract, :frozen?
        assert_equal true, contract.dig("builders", "button", "args", "positional", 0, "non_empty")
        assert_equal [ "disabled" ], contract.dig("builders", "button", "args", "keywords").keys
        refute_includes contract.fetch("types"), "action_name"
        assert_includes contract.dig("types", "button_style", "input_forms"), "symbol"
        assert_empty LanguageCatalog.generation_contract_omissions
      end

      test "exposes lookup APIs without accepting unknown language elements" do
        assert_same LanguageCatalog.builders.fetch("text"), LanguageCatalog.builder(:text)
        assert_same LanguageCatalog.modifiers.fetch("text_style"), LanguageCatalog.modifier(:text_style)
        assert_nil LanguageCatalog.builder(:script)
        assert_nil LanguageCatalog.modifier(:class)
        assert_same LanguageCatalog.statements.fetch("for_each"), LanguageCatalog.fetch(:statements, :for_each)
        assert_raises(KeyError) { LanguageCatalog.fetch(:builders, :script) }
      end

      private

      def argument_definitions(entry)
        arguments = entry.fetch("arguments", {})
        arguments.fetch("positional", []) +
          arguments.fetch("keywords", {}).values +
          arguments.fetch("syntax", [])
      end

      def assert_json_native_and_frozen(value)
        assert_predicate value, :frozen?

        case value
        when Hash
          value.each do |key, child|
            assert_instance_of String, key
            assert_predicate key, :frozen?
            assert_json_native_and_frozen(child)
          end
        when Array
          value.each { |child| assert_json_native_and_frozen(child) }
        else
          assert_includes [ String, Integer, Float, TrueClass, FalseClass, NilClass ], value.class
        end
      end
    end
  end
end
