# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class RunnerTest < ActiveSupport::TestCase
      setup do
        @view_context = ApplicationController.new.view_context
      end

      test "renders allowlisted SwiftUI Rails composition with fixture data" do
        result = run_playground(
          source: <<~'RUBY',
            vstack(alignment: :leading, spacing: 12) do
              text("Catalog for #{data[:store][:name]}").text_size("2xl").font_weight("bold")

              for_each(data[:products], id: "id") do |product|
                hstack(spacing: 8) do
                  text(product[:name])
                  if product[:in_stock]
                    badge("In Stock", tone: :success)
                  else
                    badge("Sold Out", tone: :danger)
                  end
                end
              end
            end
          RUBY
          data_json: <<~JSON
            {
              "store": { "name": "Northstar" },
              "products": [
                { "id": "keyboard", "name": "Orbit Keyboard", "in_stock": true },
                { "id": "headphones", "name": "Aurora Headphones", "in_stock": false }
              ]
            }
          JSON
        )

        assert result.success?, diagnostic_messages(result).join("\n")
        assert_includes result.html, "Catalog for Northstar"
        assert_includes result.html, "Orbit Keyboard"
        assert_includes result.html, "Aurora Headphones"
        assert_includes result.html, "In Stock"
        assert_includes result.html, "Sold Out"
        assert_empty result.diagnostics
        assert_kind_of Hash, result.stats
        assert_equal "Northstar", indifferent_fetch(indifferent_fetch(result.data, :store), :name)
      end

      test "renders the finite semantic styling vocabulary" do
        foreground_roles = %w[primary secondary tertiary quaternary accent success warning danger on_accent]
        background_roles = %w[canvas surface elevated muted accent success warning danger]
        font_roles = %w[large_title title title2 title3 headline subheadline body callout footnote caption caption2]
        text_roles = %w[title headline body supporting metadata caption]
        views = []

        foreground_roles.each { |role| views << %(text("foreground #{role}").foreground_style(:#{role})) }
        background_roles.each { |role| views << %(text("background #{role}").background_style(:#{role})) }
        font_roles.each { |role| views << %(text("font #{role}").font(:#{role})) }
        text_roles.each { |role| views << %(text("text #{role}").text_style(:#{role})) }

        result = run_playground(source: "vstack do\n#{views.join("\n")}\nend", data_json: "{}")

        assert result.success?, diagnostic_messages(result).join("\n")
        foreground_roles.each { |role| assert_includes result.html, "swift-ui-foreground-#{role.tr('_', '-')}" }
        background_roles.each { |role| assert_includes result.html, "swift-ui-background-#{role.tr('_', '-')}" }
        font_roles.each { |role| assert_includes result.html, "swift-ui-font-#{role.tr('_', '-')}" }
        text_roles.each { |role| assert_includes result.html, "swift-ui-text-style-#{role.tr('_', '-')}" }
      end

      test "rejects semantic modifiers with invalid values or arity" do
        {
          foreground_style: "brand",
          background_style: "primary",
          font: "hero",
          text_style: "marketing"
        }.each do |modifier, value|
          result = run_playground(
            source: %(text("Unsafe").#{modifier}(#{value.inspect})),
            data_json: "{}"
          )

          assert_not result.success?, "Expected #{modifier}(#{value.inspect}) to be rejected"
          assert_includes diagnostic_codes(result), "#{modifier}_value"
          assert_empty result.html
        end

        compiled = Showcase::Playground::SourceCompiler.call(
          'text("Unsafe").foreground_style(:secondary, :danger)'
        )

        assert_nil compiled.program
        assert_equal [ "modifier_arguments" ], compiled.diagnostics.map { |diagnostic| diagnostic.fetch(:code) }
      end

      test "renders curated examples entirely through semantic presentation roles" do
        Showcase::Playground::Examples.all.each do |example|
          result = run_playground(source: example.source, data_json: example.data_json)

          assert result.success?, "#{example.name}: #{diagnostic_messages(result).join("; ")}"
          assert_includes result.html, "swift-ui-text-style-"
          assert_includes result.html, "swift-ui-background-"
          refute_match(/\.(?:text_color|text_size|font_weight|bg|border_color)\(/, example.source, example.name)
          refute_match(
            /(?:stimulus_|data[_-](?:controller|action)|playground_action|->[^#\s]+#|javascript|query_selector|dom_mutation)/i,
            example.source,
            example.name
          )
          refute_includes result.html, "data-playground-action"
        end

        product = run_playground(
          source: Showcase::Playground::Examples::PRODUCT_CATALOG_SOURCE,
          data_json: Showcase::Playground::Examples::PRODUCT_CATALOG_DATA
        )
        assert_includes product.html, "swift-ui-foreground-warning"
        assert_includes product.html, "swift-ui-foreground-accent"
        assert_includes product.html, "swift-ui-foreground-success"
        refute_includes product.html, "text-amber-600"
      end

      test "supports unless and a bounded for_each block" do
        result = run_playground(
          source: <<~'RUBY',
            vstack(spacing: 8) do
              for_each(data[:alerts], id: "id") do |alert|
                unless alert[:resolved]
                  text("Open: #{alert[:message]}")
                end
              end
            end
          RUBY
          data_json: <<~JSON
            {
              "alerts": [
                { "id": "fuel", "message": "Check fuel", "resolved": false },
                { "id": "charts", "message": "Load charts", "resolved": true }
              ]
            }
          JSON
        )

        assert result.success?, diagnostic_messages(result).join("\n")
        assert_includes result.html, "Open: Check fuel"
        refute_includes result.html, "Load charts"
      end

      test "for_each gives every direct text and card root stable RenderIR and DOM identity" do
        source = <<~'RUBY'
          vstack do
            for_each(data[:products], id: "id") do |product|
              text(product[:name])
              article do
                text("Card: #{product[:name]}")
              end
            end
          end
        RUBY
        products = [
          { id: 1, name: "Orbit Keyboard" },
          { id: "1", name: "Aurora Headphones" }
        ]

        first = run_playground(source: source, data_json: JSON.generate(products: products))
        reordered = run_playground(source: source, data_json: JSON.generate(products: products.reverse))

        assert first.success?, diagnostic_messages(first).join("\n")
        assert reordered.success?, diagnostic_messages(reordered).join("\n")
        first_roots = first.render_ir.root.children.fetch(0).children
        reordered_roots = reordered.render_ir.root.children.fetch(0).children
        first_identities = first_roots.to_h { |node| [ [ node.kind, render_ir_text(node) ], node.identity ] }
        reordered_identities = reordered_roots.to_h { |node| [ [ node.kind, render_ir_text(node) ], node.identity ] }

        assert_equal 4, first_roots.length
        assert first_roots.all?(&:identity)
        assert_equal 4, first_roots.map(&:identity).uniq.length
        assert_equal first_identities, reordered_identities

        identified_elements = Nokogiri::HTML.fragment(first.html).css("[data-morph-id]")
        dom_identities = identified_elements.map do |element|
          element["data-morph-id"]
        end
        assert_equal first_roots.map(&:identity).sort, dom_identities.sort
        assert identified_elements.all? { |element| element["id"] == element["data-morph-id"] }
        assert dom_identities.all? { |identity| identity.match?(/\Aswift-ui-ir-[0-9a-f]{32}\z/) }
      end

      test "nested for_each identities include their parent item and remain stable when reordered" do
        source = <<~'RUBY'
          vstack do
            for_each(data[:groups], id: "id") do |group|
              vstack do
                for_each(group[:items], id: "id") do |item|
                  text("#{group[:name]}: #{item[:name]}")
                end
              end
            end
          end
        RUBY
        groups = [
          {
            id: "hardware",
            name: "Hardware",
            items: [
              { id: "shared", name: "Shared key" },
              { id: "unique", name: "Keyboard" }
            ]
          },
          {
            id: "audio",
            name: "Audio",
            items: [
              { id: "shared", name: "Shared key" },
              { id: "unique", name: "Headphones" }
            ]
          }
        ]
        reordered_groups = groups.reverse.map { |group| group.merge(items: group.fetch(:items).reverse) }

        first = run_playground(source: source, data_json: JSON.generate(groups: groups))
        reordered = run_playground(source: source, data_json: JSON.generate(groups: reordered_groups))

        assert first.success?, diagnostic_messages(first).join("\n")
        assert reordered.success?, diagnostic_messages(reordered).join("\n")
        first_identified = first.render_ir.each_node.select(&:identity)
        reordered_identified = reordered.render_ir.each_node.select(&:identity)
        first_nested = first_identified.select { |node| node.kind == "text" }
        reordered_nested = reordered_identified.select { |node| node.kind == "text" }

        assert_equal 6, first_identified.length
        assert_equal 6, first_identified.map(&:identity).uniq.length
        assert_equal first_identified.map(&:identity).sort, reordered_identified.map(&:identity).sort
        assert_equal(
          first_nested.to_h { |node| [ render_ir_text(node), node.identity ] },
          reordered_nested.to_h { |node| [ render_ir_text(node), node.identity ] }
        )
      end

      test "returns a located diagnostic for invalid syntax" do
        result = run_playground(
          source: <<~RUBY,
            vstack do
              text("Missing end")
          RUBY
          data_json: "{}"
        )

        assert_not result.success?
        diagnostic = result.diagnostics.first
        assert diagnostic, "Expected a syntax diagnostic"
        assert_match(/syntax|parse|unexpected|end/i, diagnostic_value(diagnostic, :message).to_s)
        assert_operator diagnostic_value(diagnostic, :line).to_i, :>=, 1
        assert_operator diagnostic_value(diagnostic, :column).to_i, :>=, 0
        assert_empty result.html.to_s
      end

      test "returns a useful diagnostic for malformed fixture JSON" do
        result = run_playground(
          source: 'text("Hello")',
          data_json: '{"title": "unterminated}'
        )

        assert_not result.success?
        assert_match(/json|fixture|data/i, diagnostic_messages(result).join(" "))
        assert_empty result.html.to_s
      end

      test "requires fixture data to be a top-level object" do
        result = run_playground(
          source: 'text("Hello")',
          data_json: '[{"title":"not a root object"}]'
        )

        assert_not result.success?
        assert_match(/object|fixture|data/i, diagnostic_messages(result).join(" "))
      end

      test "rejects NUL bytes in fixture JSON before parsing" do
        result = run_playground(
          source: 'text("Hello")',
          data_json: "{\"title\":\"safe\"}\0{\"title\":\"shadow\"}"
        )

        assert_not result.success?
        assert_includes diagnostic_codes(result), "data_encoding"
        assert_match(/UTF-8|NUL/i, diagnostic_messages(result).join(" "))
        assert_empty result.html
      end

      test "rejects duplicate fixture keys including escaped equivalents" do
        direct = run_playground(
          source: "text(data[:title])",
          data_json: '{"title":"first","title":"second"}'
        )
        escaped = run_playground(
          source: "text(data[:title])",
          data_json: '{"title":"first","\\u0074itle":"second"}'
        )

        [ direct, escaped ].each do |result|
          assert_not result.success?
          assert_includes diagnostic_codes(result), "data_duplicate_key"
          assert_equal "$.title", result.diagnostics.first.fetch("path")
          assert_empty result.html
        end
      end

      test "rejects huge fixture integers and overflowing arithmetic results" do
        huge_fixture = run_playground(
          source: "text(data[:value])",
          data_json: JSON.generate(value: 1_000_000_000_001)
        )

        assert_not huge_fixture.success?
        assert_includes diagnostic_codes(huge_fixture), "data_number"
        assert_match(/finite|bounded|number/i, diagnostic_messages(huge_fixture).join(" "))

        arithmetic_overflow = run_playground(
          source: "text(data[:left] * data[:right])",
          data_json: JSON.generate(left: 1_000_000_000, right: 1_000_000_000)
        )

        assert_not arithmetic_overflow.success?
        assert_includes diagnostic_codes(arithmetic_overflow), "number_range"
        assert_match(/arithmetic|finite|bounded/i, diagnostic_messages(arithmetic_overflow).join(" "))
        assert_empty arithmetic_overflow.html
      end

      test "uses the catalogue as the source of truth for numeric literal bounds" do
        integer_limit = LanguageCatalog.types.fetch("integer").fetch("maximum_magnitude")
        number_limit = LanguageCatalog.types.fetch("number").fetch("maximum_magnitude")

        accepted_integer = SourceCompiler.call("text(#{integer_limit})")
        rejected_integer = SourceCompiler.call("text(#{integer_limit + 1})")
        accepted_float = SourceCompiler.call("text(#{number_limit.to_f})")
        rejected_float = SourceCompiler.call("text(#{number_limit.to_f * 10})")

        assert_empty accepted_integer.diagnostics
        assert_empty accepted_float.diagnostics
        assert_equal "number_range", rejected_integer.diagnostics.first.fetch(:code)
        assert_equal "number_range", rejected_float.diagnostics.first.fetch(:code)
      end

      test "uses catalogue bounds for numeric fixture expressions at render time" do
        positive_total = run_playground(
          source: "progress_view(total: data[:total])",
          data_json: JSON.generate(total: 0.0000001)
        )
        invalid_columns = run_playground(
          source: "grid(columns: data[:columns]) { text(\"Item\") }",
          data_json: JSON.generate(columns: LanguageCatalog.builder("grid").dig("arguments", "keywords", "columns", "maximum") + 1)
        )

        assert positive_total.success?, diagnostic_messages(positive_total).join("\n")
        assert_includes positive_total.html, "<progress"
        assert_not invalid_columns.success?
        assert_includes diagnostic_codes(invalid_columns), "columns_range"
      end

      test "rejects empty accessible control labels for literals and fixture data" do
        literal = run_playground(source: 'button("")', data_json: "{}")
        button_fixture = run_playground(source: "button(data[:label])", data_json: JSON.generate(label: " \n "))
        progress_fixture = run_playground(source: "progress_view(label: data[:label])", data_json: JSON.generate(label: ""))
        gauge_fixture = run_playground(source: "gauge(value: 50, label: data[:label])", data_json: JSON.generate(label: "  "))

        [ literal, button_fixture, progress_fixture, gauge_fixture ].each do |result|
          assert_not result.success?
          assert_includes diagnostic_codes(result), "label_required"
          assert_nil result.artifact
        end
      end

      test "deeply freezes result diagnostics so callers cannot change success" do
        result = run_playground(source: 'button("")', data_json: "{}")

        assert_not result.success?
        assert_predicate result.diagnostics, :frozen?
        assert_predicate result.diagnostics.first, :frozen?
        assert_raises(FrozenError) { result.diagnostics.first["severity"] = "warning" }
        assert_not result.success?
        assert_equal false, result.as_json.fetch(:ok)
      end

      test "escapes fixture strings instead of promoting them to markup" do
        result = run_playground(
          source: "vstack { text(data[:title]); text(data[:description]) }",
          data_json: {
            title: '<script id="fixture-script">alert(1)</script>',
            description: '<img id="fixture-image" src=x onerror=alert(1)>'
          }.to_json
        )

        assert result.success?, diagnostic_messages(result).join("\n")
        refute_includes result.html, '<script id="fixture-script">'
        refute_includes result.html, '<img id="fixture-image"'
        assert_includes result.html, "&lt;script"
        assert_includes result.html, "&lt;img"
      end

      test "enforces source and fixture byte limits before interpretation" do
        source_limit = playground_limit(:SOURCE_BYTES, 32.kilobytes)
        source_result = run_playground(
          source: "x" * (source_limit + 1),
          data_json: "{}"
        )

        assert_not source_result.success?
        assert_match(/source|code/i, diagnostic_messages(source_result).join(" "))
        assert_match(/limit|large|long|bytes/i, diagnostic_messages(source_result).join(" "))

        data_limit = playground_limit(:DATA_BYTES, 64.kilobytes)
        data_result = run_playground(
          source: 'text("Hello")',
          data_json: JSON.generate(payload: "x" * data_limit)
        )

        assert_not data_result.success?
        assert_match(/data|fixture|json/i, diagnostic_messages(data_result).join(" "))
        assert_match(/limit|large|long|bytes/i, diagnostic_messages(data_result).join(" "))
      end

      test "oversized source wins over malformed fixture data without scanning source lines" do
        source_limit = playground_limit(:SOURCE_BYTES, 32.kilobytes)
        result = run_playground(
          source: "x" * (source_limit + 1),
          data_json: "{malformed"
        )

        assert_not result.success?
        assert_equal [ "source_size" ], diagnostic_codes(result)
        assert_equal 0, indifferent_fetch(result.stats, :source_lines)
        assert_empty result.html
        assert_equal({}, result.data)
      end

      test "repeated maximum-sized fixture text hits the cumulative render budget" do
        text_bytes = playground_limit(:DATA_STRING_BYTES, 8.kilobytes)
        item_count = (playground_limit(:RENDERED_TEXT_BYTES, 192.kilobytes) / text_bytes) + 1
        result = run_playground(
          source: <<~RUBY,
            vstack do
              for_each(data[:items], id: "id") do |item|
                text(data[:payload])
              end
            end
          RUBY
          data_json: JSON.generate(
            payload: "x" * text_bytes,
            items: Array.new(item_count) { |index| { id: "item-#{index}" } }
          )
        )

        assert_not result.success?
        assert_includes diagnostic_codes(result), "text_size"
        assert_match(/rendered text|limited/i, diagnostic_messages(result).join(" "))
        assert_empty result.html
        assert_equal 0, indifferent_fetch(result.stats, :html_bytes)
      end

      private

      def render_ir_text(node)
        node.each_node
          .select { |child| child.kind == "text_literal" }
          .map { |child| child.props.fetch("value") }
          .join
      end

      def run_playground(source:, data_json:)
        Showcase::Playground::Runner.call(
          source: source,
          data_json: data_json,
          view_context: @view_context
        )
      end

      def playground_limit(name, fallback)
        if Showcase::Playground::Limits.const_defined?(name, false)
          Showcase::Playground::Limits.const_get(name)
        else
          fallback
        end
      end

      def diagnostic_messages(result)
        Array(result.diagnostics).map { |diagnostic| diagnostic_value(diagnostic, :message).to_s }
      end

      def diagnostic_codes(result)
        Array(result.diagnostics).map { |diagnostic| diagnostic_value(diagnostic, :code).to_s }
      end

      def diagnostic_value(diagnostic, key)
        return diagnostic.public_send(key) if diagnostic.respond_to?(key)

        diagnostic[key] || diagnostic[key.to_s]
      end

      def indifferent_fetch(hash, key)
        hash.fetch(key) { hash.fetch(key.to_s) }
      end
    end
  end
end
