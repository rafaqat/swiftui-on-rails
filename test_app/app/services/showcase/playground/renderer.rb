# frozen_string_literal: true

require "json"
require "set"

module Showcase
  module Playground
    class Renderer
      SymbolValue = Struct.new(:name) do
        def initialize(name)
          super(name.to_s.freeze)
          freeze
        end
      end

      RenderResult = Struct.new(
        :html,
        :diagnostics,
        :view_count,
        :iteration_count,
        :operation_count,
        :render_ir,
        keyword_init: true
      )

      def self.enum_mapping(type)
        LanguageCatalog.types.fetch(type).fetch("values").to_h { |value| [ value, value.to_sym ] }.freeze
      end

      ALIGNMENTS = enum_mapping("alignment")
      STACK_ALIGNMENTS = enum_mapping("stack_alignment")
      BADGE_TONES = enum_mapping("badge_tone")
      BUTTON_STYLES = enum_mapping("button_style")
      BUTTON_SIZES = enum_mapping("button_size")
      TEXT_SIZES = LanguageCatalog.types.fetch("text_size").fetch("values")
      FONT_WEIGHTS = LanguageCatalog.types.fetch("font_weight").fetch("values")
      FOREGROUND_STYLES = enum_mapping("foreground_style")
      BACKGROUND_STYLES = enum_mapping("background_style")
      FONTS = enum_mapping("font")
      TEXT_STYLES = enum_mapping("text_style")
      ROUNDED = LanguageCatalog.types.fetch("corner_radius").fetch("values")
      SHADOWS = LanguageCatalog.types.fetch("shadow").fetch("values")
      BORDER_WIDTHS = LanguageCatalog.types.fetch("border_width").fetch("values")
      OPACITIES = LanguageCatalog.types.fetch("opacity").fetch("values")
      SPACING = LanguageCatalog.types.fetch("spacing").fetch("values")
      SIZES = LanguageCatalog.types.fetch("size").fetch("values")
      MAX_SIZES = LanguageCatalog.types.fetch("max_size").fetch("values")
      COLOR_FORMS = LanguageCatalog.types.fetch("safe_color").fetch("forms")
      COLOR_NAMES = COLOR_FORMS.first.fetch("name_values")
      SHADEABLE_COLOR_NAMES = COLOR_FORMS.last.fetch("name_values")
      COLOR_SHADES = COLOR_FORMS.last.fetch("shade_values")
      IDENTIFIER_KEY_PATTERN = LanguageCatalog.types.fetch("identifier_key").fetch("pattern")
      IDENTIFIER_KEY = Regexp.new("\\A(?:#{IDENTIFIER_KEY_PATTERN})\\z")
      MAX_NUMBER_MAGNITUDE = LanguageCatalog.types.fetch("number").fetch("maximum_magnitude")
      IDENTITY_ANCESTRY_KEY = Object.new.freeze

      def self.call(program:, data:, view_context:)
        new(program: program, data: data, view_context: view_context).call
      end

      def initialize(program:, data:, view_context:)
        @document = IntermediateRepresentation.wrap(
          program,
          language_version: LanguageCatalog::VERSION
        )
        @program = @document.program
        @data = data
        @view_context = view_context
        @view_count = 0
        @iteration_count = 0
        @operation_count = 0
        @rendered_text_bytes = 0
      end

      def call
        context = SwiftUIRails::DSLContext.new(@view_context)
        render_statement(@program, context, { "data" => @data }.freeze)
        html = context.flush_elements.to_s
        fail_at(@program, "html_size", "The rendered preview is larger than #{Limits::HTML_BYTES / 1024} KiB.") if html.bytesize > Limits::HTML_BYTES

        RenderResult.new(
          html: html,
          diagnostics: [],
          view_count: @view_count,
          iteration_count: @iteration_count,
          operation_count: @operation_count,
          render_ir: context.last_render_ir
        )
      rescue RuntimeFailure => error
        RenderResult.new(
          html: "",
          diagnostics: [ error.diagnostic ],
          view_count: @view_count,
          iteration_count: @iteration_count,
          operation_count: @operation_count,
          render_ir: nil
        )
      rescue ArgumentError, TypeError => error
        Rails.logger.info("[Playground] Fixed renderer rejected values: #{error.class}: #{error.message}")
        diagnostic = runtime_diagnostic(@program, "invalid_value", "A view or modifier received an unsupported value.")
        RenderResult.new(
          html: "",
          diagnostics: [ diagnostic ],
          view_count: @view_count,
          iteration_count: @iteration_count,
          operation_count: @operation_count,
          render_ir: nil
        )
      end

      # DSL layout elements execute their child blocks later while HTML is
      # flushed. Expose one narrow trusted callback for those closures; the
      # submitted source can never name or dispatch this Ruby method.
      def render_children(nodes, context, environment)
        render_statements(nodes, context, environment)
      end

      private

      RuntimeFailure = Class.new(StandardError) do
        attr_reader :diagnostic

        def initialize(diagnostic)
          @diagnostic = diagnostic
          super(diagnostic.fetch(:message))
        end
      end

      def render_statement(node, context, environment)
        tick!
        case node.fetch("type")
        when "view"
          render_view(node, context, environment)
        when "if"
          branch = truthy?(evaluate(node.fetch("predicate"), environment)) ? node.fetch("then") : node.fetch("else")
          render_statements(branch, context, environment)
        when "unless"
          branch = truthy?(evaluate(node.fetch("predicate"), environment)) ? node.fetch("else") : node.fetch("then")
          render_statements(branch, context, environment)
        when "for_each"
          render_collection(node, context, environment)
        else
          fail_at(node, "invalid_ir", "The compiled playground program is invalid.")
        end
      end

      def render_statements(nodes, context, environment)
        nodes.each { |node| render_statement(node, context, environment) }
      end

      def render_view(node, context, environment)
        @view_count += 1
        fail_at(node, "view_limit", "A preview may render at most #{Limits::RENDERED_VIEWS} views.") if @view_count > Limits::RENDERED_VIEWS

        arguments = node.fetch("arguments").map { |argument| evaluate(argument, environment) }
        keywords = node.fetch("keywords").transform_values { |value| evaluate(value, environment) }
        renderer = self

        element = case node.fetch("name")
        when "vstack"
          alignment = enum_value(catalog_keyword(keywords, node, "alignment"), STACK_ALIGNMENTS, node, "alignment")
          spacing = catalog_number(keywords, node, "spacing")
          context.vstack(alignment: alignment, spacing: spacing) { renderer.render_children(node.fetch("children"), self, environment) }
        when "hstack"
          alignment = enum_value(catalog_keyword(keywords, node, "alignment"), STACK_ALIGNMENTS, node, "alignment")
          spacing = catalog_number(keywords, node, "spacing")
          context.hstack(alignment: alignment, spacing: spacing) { renderer.render_children(node.fetch("children"), self, environment) }
        when "zstack"
          alignment = enum_value(catalog_keyword(keywords, node, "alignment"), ALIGNMENTS, node, "alignment")
          context.zstack(alignment: alignment) { renderer.render_children(node.fetch("children"), self, environment) }
        when "grid"
          columns = catalog_number(keywords, node, "columns")
          spacing = catalog_number(keywords, node, "spacing")
          context.grid(columns: columns, spacing: spacing) { renderer.render_children(node.fetch("children"), self, environment) }
        when "section"
          context.section { renderer.render_children(node.fetch("children"), self, environment) }
        when "article"
          context.article { renderer.render_children(node.fetch("children"), self, environment) }
        when "text"
          context.text(text_value(arguments.fetch(0), node))
        when "button"
          disabled = boolean_value(catalog_keyword(keywords, node, "disabled"), node, "disabled")
          context.button(catalog_text_argument(arguments, node, 0), disabled: disabled)
        when "badge"
          tone = enum_value(catalog_keyword(keywords, node, "tone"), BADGE_TONES, node, "tone")
          announce = boolean_value(catalog_keyword(keywords, node, "announce"), node, "announce")
          context.badge(text_value(arguments.fetch(0), node), tone: tone, announce: announce)
        when "icon"
          name = string_or_symbol(arguments.fetch(0), node, "icon")
          fail_at(node, "icon_name", "Unknown icon `#{name}`.") unless SwiftUIRails::DSL::ICON_GLYPHS.key?(name)
          size = catalog_number(keywords, node, "size")
          context.icon(name, size: size)
        when "spacer"
          min_length = catalog_number(keywords, node, "min_length")
          context.spacer(min_length: min_length)
        when "divider"
          context.divider
        when "progress_view"
          value = catalog_number(keywords, node, "value")
          total = catalog_number(keywords, node, "total")
          label = catalog_text_keyword(keywords, node, "label")
          context.progress_view(value: value, total: total, label: label)
        when "gauge"
          value = catalog_number(keywords, node, "value")
          label = catalog_text_keyword(keywords, node, "label")
          context.gauge(value: value, label: label)
        else
          fail_at(node, "invalid_view", "The compiled view is not supported.")
        end

        apply_modifiers(element, node.fetch("modifiers"), environment)
      end

      def apply_modifiers(element, modifiers, environment)
        modifiers.each do |modifier|
          arguments = modifier.fetch("arguments").map { |argument| evaluate(argument, environment) }
          name = modifier.fetch("name")
          case name
          when "p" then element.p(spacing_value(arguments.fetch(0), modifier))
          when "px" then element.px(spacing_value(arguments.fetch(0), modifier))
          when "py" then element.py(spacing_value(arguments.fetch(0), modifier))
          when "pt" then element.pt(spacing_value(arguments.fetch(0), modifier))
          when "pr" then element.pr(spacing_value(arguments.fetch(0), modifier))
          when "pb" then element.pb(spacing_value(arguments.fetch(0), modifier))
          when "pl" then element.pl(spacing_value(arguments.fetch(0), modifier))
          when "m" then element.m(spacing_value(arguments.fetch(0), modifier))
          when "mx" then element.mx(spacing_value(arguments.fetch(0), modifier))
          when "my" then element.my(spacing_value(arguments.fetch(0), modifier))
          when "mt" then element.mt(spacing_value(arguments.fetch(0), modifier))
          when "mr" then element.mr(spacing_value(arguments.fetch(0), modifier))
          when "mb" then element.mb(spacing_value(arguments.fetch(0), modifier))
          when "ml" then element.ml(spacing_value(arguments.fetch(0), modifier))
          when "padding" then element.padding(spacing_value(arguments.fetch(0), modifier))
          when "bg" then element.bg(color_value(arguments.fetch(0), modifier))
          when "text_color" then element.text_color(color_value(arguments.fetch(0), modifier))
          when "text_size" then element.text_size(enum_name(arguments.fetch(0), TEXT_SIZES, modifier, "text size"))
          when "font_weight" then element.font_weight(enum_name(arguments.fetch(0), FONT_WEIGHTS, modifier, "font weight"))
          when "foreground_style" then element.foreground_style(enum_value(arguments.fetch(0), FOREGROUND_STYLES, modifier, "foreground style"))
          when "background_style" then element.background_style(enum_value(arguments.fetch(0), BACKGROUND_STYLES, modifier, "background style"))
          when "font" then element.font(enum_value(arguments.fetch(0), FONTS, modifier, "font"))
          when "text_style" then element.text_style(enum_value(arguments.fetch(0), TEXT_STYLES, modifier, "text style"))
          when "rounded"
            arguments.empty? ? element.rounded : element.rounded(enum_name(arguments.fetch(0), ROUNDED, modifier, "corner radius"))
          when "shadow"
            arguments.empty? ? element.shadow : element.shadow(enum_name(arguments.fetch(0), SHADOWS, modifier, "shadow"))
          when "border"
            arguments.empty? ? element.border : element.border(enum_name(arguments.fetch(0), BORDER_WIDTHS, modifier, "border width"))
          when "border_color" then element.border_color(color_value(arguments.fetch(0), modifier))
          when "opacity" then element.opacity(enum_name(arguments.fetch(0), OPACITIES, modifier, "opacity"))
          when "w" then element.w(enum_name(arguments.fetch(0), SIZES, modifier, "width"))
          when "h" then element.h(enum_name(arguments.fetch(0), SIZES, modifier, "height"))
          when "min_w" then element.min_w(enum_name(arguments.fetch(0), SIZES, modifier, "minimum width"))
          when "min_h" then element.min_h(enum_name(arguments.fetch(0), SIZES, modifier, "minimum height"))
          when "max_w" then element.max_w(enum_name(arguments.fetch(0), MAX_SIZES, modifier, "maximum width"))
          when "max_h" then element.max_h(enum_name(arguments.fetch(0), MAX_SIZES, modifier, "maximum height"))
          when "hidden" then element.hidden(arguments.empty? ? true : boolean_value(arguments.fetch(0), modifier, "hidden"))
          when "disabled" then element.disabled(arguments.empty? ? true : boolean_value(arguments.fetch(0), modifier, "disabled"))
          when "button_style" then element.button_style(enum_value(arguments.fetch(0), BUTTON_STYLES, modifier, "button style"))
          when "button_size" then element.button_size(enum_value(arguments.fetch(0), BUTTON_SIZES, modifier, "button size"))
          when "w_full" then element.w_full
          else fail_at(modifier, "invalid_modifier", "The compiled modifier is not supported.")
          end
        end
        element
      end

      def render_collection(node, context, environment)
        collection = evaluate(node.fetch("collection"), environment)
        fail_at(node, "for_each_type", "`for_each` requires an array from the test data.") unless collection.is_a?(Array)
        fail_at(node, "loop_limit", "A single `for_each` may render at most #{Limits::LOOP_ITERATIONS} items.") if collection.length > Limits::LOOP_ITERATIONS

        id_key = string_value(evaluate(node.fetch("id"), environment), node, "id")
        fail_at(node, "for_each_id", "The `id:` value must name a JSON key.") unless IDENTIFIER_KEY.match?(id_key)
        seen_ids = Set.new

        collection.each do |item|
          @iteration_count += 1
          fail_at(node, "loop_total", "A preview may perform at most #{Limits::TOTAL_LOOP_ITERATIONS} loop iterations.") if @iteration_count > Limits::TOTAL_LOOP_ITERATIONS
          fail_at(node, "for_each_item", "Each `for_each` item must be a JSON object.") unless item.is_a?(Hash)
          fail_at(node, "for_each_id", "Each item must contain the stable key `#{id_key}`.") unless item.key?(id_key)

          identity = item.fetch(id_key)
          unless identity.is_a?(String) || identity.is_a?(Integer)
            fail_at(node, "for_each_id", "Stable item identifiers must be strings or integers.")
          end
          identity_key = "#{identity.class}:#{identity}"
          fail_at(node, "duplicate_id", "Each `for_each` item needs a unique `#{id_key}` value.") if seen_ids.include?(identity_key)
          seen_ids.add(identity_key)

          identity_scope = collection_identity_scope(node, id_key, identity, environment)
          child_environment = environment.merge(
            node.fetch("variable") => item,
            IDENTITY_ANCESTRY_KEY => identity_scope
          ).freeze
          context.with_render_identity_scope(JSON.generate(identity_scope)) do
            render_statements(node.fetch("children"), context, child_environment)
          end
        end
      end

      def collection_identity_scope(node, id_key, identity, environment)
        location = node.fetch("location")
        segment = [
          "for_each",
          location.fetch("line"),
          location.fetch("column"),
          location.fetch("end_line"),
          location.fetch("end_column"),
          id_key,
          identity.is_a?(String) ? "string" : "integer",
          identity.to_s
        ].freeze

        (environment.fetch(IDENTITY_ANCESTRY_KEY, []) + [ segment ]).freeze
      end

      def evaluate(expression, environment)
        tick!
        case expression.fetch("type")
        when "literal"
          expression["value"]
        when "symbol"
          SymbolValue.new(expression.fetch("value"))
        when "variable"
          environment.fetch(expression.fetch("name")) { fail_at(expression, "unknown_variable", "The variable is not available in this scope.") }
        when "index"
          evaluate_index(expression, environment)
        when "interpolation"
          expression.fetch("parts").map { |part| scalar_text(evaluate(part, environment), part) }.join
        when "boolean"
          evaluate_boolean(expression, environment)
        when "not"
          !truthy?(evaluate(expression.fetch("value"), environment))
        when "binary"
          evaluate_binary(expression, environment)
        when "operation"
          evaluate_operation(expression, environment)
        else
          fail_at(expression, "invalid_expression", "The compiled expression is invalid.")
        end
      end

      def evaluate_index(expression, environment)
        receiver = evaluate(expression.fetch("receiver"), environment)
        key = evaluate(expression.fetch("key"), environment)
        key = key.name if key.is_a?(SymbolValue)

        case receiver
        when Hash
          fail_at(expression, "missing_key", "Test data does not contain `#{key}`.") unless key.is_a?(String) && receiver.key?(key)
          receiver.fetch(key)
        when Array
          fail_at(expression, "array_index", "Array indexes must be non-negative integers.") unless key.is_a?(Integer) && key >= 0 && key < receiver.length
          receiver.fetch(key)
        else
          fail_at(expression, "index_type", "Only JSON objects and arrays can be indexed.")
        end
      end

      def evaluate_boolean(expression, environment)
        left = evaluate(expression.fetch("left"), environment)
        if expression.fetch("operator") == "&&"
          truthy?(left) ? evaluate(expression.fetch("right"), environment) : left
        else
          truthy?(left) ? left : evaluate(expression.fetch("right"), environment)
        end
      end

      def evaluate_binary(expression, environment)
        left = evaluate(expression.fetch("left"), environment)
        right = evaluate(expression.fetch("right"), environment)
        operator = expression.fetch("operator")

        case operator
        when "==" then comparable_value(left) == comparable_value(right)
        when "!=" then comparable_value(left) != comparable_value(right)
        when "<", "<=", ">", ">="
          unless (left.is_a?(Numeric) && right.is_a?(Numeric)) || (left.is_a?(String) && right.is_a?(String))
            fail_at(expression, "comparison_type", "Ordered comparisons require two numbers or two strings.")
          end
          { "<" => left < right, "<=" => left <= right, ">" => left > right, ">=" => left >= right }.fetch(operator)
        when "+", "-", "*", "/"
          unless left.is_a?(Numeric) && right.is_a?(Numeric)
            fail_at(expression, "arithmetic_type", "Arithmetic requires numeric values.")
          end
          fail_at(expression, "division_zero", "Cannot divide by zero.") if operator == "/" && right.zero?
          value = { "+" => left + right, "-" => left - right, "*" => left * right, "/" => left.to_f / right }.fetch(operator)
          unless (!value.is_a?(Float) || value.finite?) && value.abs <= MAX_NUMBER_MAGNITUDE
            fail_at(expression, "number_range", "The arithmetic result must be finite and bounded.")
          end
          value
        else
          fail_at(expression, "invalid_operator", "The compiled operator is invalid.")
        end
      end

      def evaluate_operation(expression, environment)
        receiver = evaluate(expression.fetch("receiver"), environment)
        operator = expression.fetch("operator")
        case operator
        when "count", "length", "size"
          fail_at(expression, "operation_type", "`.#{operator}` requires an array, object, or string.") unless receiver.is_a?(Array) || receiver.is_a?(Hash) || receiver.is_a?(String)
          receiver.length
        when "empty?"
          fail_at(expression, "operation_type", "`.empty?` requires an array, object, or string.") unless receiver.is_a?(Array) || receiver.is_a?(Hash) || receiver.is_a?(String)
          receiver.empty?
        when "first", "last"
          fail_at(expression, "operation_type", "`.#{operator}` requires an array or string.") unless receiver.is_a?(Array) || receiver.is_a?(String)
          operator == "first" ? receiver.first : receiver.last
        else
          fail_at(expression, "invalid_operation", "The compiled operation is invalid.")
        end
      end

      def comparable_value(value)
        value.is_a?(SymbolValue) ? value.name : value
      end

      def truthy?(value)
        value != false && !value.nil?
      end

      def tick!
        @operation_count += 1
        fail_at(@program, "operation_limit", "The preview exceeded its deterministic operation budget.") if @operation_count > Limits::EVALUATOR_OPERATIONS
      end

      def text_value(value, node)
        text = scalar_text(value, node)
        @rendered_text_bytes += text.bytesize
        if @rendered_text_bytes > Limits::RENDERED_TEXT_BYTES
          fail_at(node, "text_size", "Rendered text is limited to #{Limits::RENDERED_TEXT_BYTES / 1024} KiB.")
        end
        text
      end

      def catalog_text_argument(arguments, node, index)
        text = text_value(arguments.fetch(index), node)
        specification = LanguageCatalog.builder(node.fetch("name")).fetch("arguments").fetch("positional").fetch(index)
        validate_catalog_text(text, specification, node, specification.fetch("name"))
      end

      def catalog_text_keyword(keywords, node, name)
        text = text_value(catalog_keyword(keywords, node, name), node)
        validate_catalog_text(text, catalog_keyword_spec(node, name), node, name)
      end

      def validate_catalog_text(text, specification, node, name)
        if specification["non_empty"] && text.strip.empty?
          fail_at(node, "#{name}_required", "`#{name}` must provide a non-empty accessible name.")
        end
        text
      end

      def scalar_text(value, node)
        case value
        when String then value
        when Integer, Float, TrueClass, FalseClass then value.to_s
        when NilClass then ""
        when SymbolValue then value.name
        else
          fail_at(node, "text_type", "Text content must be a JSON scalar, not a collection.")
        end
      end

      def string_value(value, node, name)
        return value if value.is_a?(String) && value.bytesize <= 256

        fail_at(node, "#{name}_type", "`#{name}` must be a short string.")
      end

      def string_or_symbol(value, node, name)
        return value.name if value.is_a?(SymbolValue)
        return value if value.is_a?(String) && value.bytesize <= 128

        fail_at(node, "#{name}_type", "`#{name}` must be a string or literal symbol.")
      end

      def boolean_value(value, node, name)
        return value if value == true || value == false

        fail_at(node, "#{name}_type", "`#{name}` must be true or false.")
      end

      def catalog_keyword(keywords, node, name)
        return keywords.fetch(name) if keywords.key?(name)

        specification = catalog_keyword_spec(node, name)
        return specification["default"] if specification.key?("default")

        fail_at(node, "missing_keyword", "`#{node.fetch('name')}` requires `#{name}:`.")
      end

      def catalog_number(keywords, node, name)
        value = catalog_keyword(keywords, node, name)
        return if value.nil?

        specification = catalog_keyword_spec(node, name)
        definition = LanguageCatalog.types.fetch(specification.fetch("type"))
        constraints = definition.merge(specification)
        integer = definition.fetch("kind") == "integer"
        valid = integer ? value.is_a?(Integer) : value.is_a?(Numeric)
        valid &&= !value.is_a?(Float) || value.finite?

        maximum_magnitude = constraints["maximum_magnitude"]
        valid &&= value.abs <= maximum_magnitude if valid && maximum_magnitude
        valid &&= value >= constraints["minimum"] if valid && constraints.key?("minimum")
        valid &&= value > constraints["minimum_exclusive"] if valid && constraints.key?("minimum_exclusive")
        valid &&= value <= constraints["maximum"] if valid && constraints.key?("maximum")
        valid &&= value < constraints["maximum_exclusive"] if valid && constraints.key?("maximum_exclusive")

        expected = integer ? "an integer" : "a finite number"
        fail_at(node, "#{name}_range", "`#{name}` must be #{expected} inside the catalogue's bounded range.") unless valid
        value
      end

      def catalog_keyword_spec(node, name)
        LanguageCatalog.builder(node.fetch("name")).fetch("arguments").fetch("keywords").fetch(name)
      end

      def spacing_value(value, node)
        enum_name(value, SPACING, node, "spacing")
      end

      def color_value(value, node)
        name = string_or_symbol(value, node, "color")
        valid = COLOR_NAMES.include?(name) || begin
          color, shade = name.split("-", 2)
          SHADEABLE_COLOR_NAMES.include?(color) && COLOR_SHADES.include?(shade)
        end
        fail_at(node, "color_value", "Unknown safe color `#{name}`.") unless valid
        name
      end

      def enum_value(value, mapping, node, name)
        key = string_or_symbol(value, node, name)
        mapping.fetch(key) { fail_at(node, "#{name.tr(' ', '_')}_value", "Unknown #{name} `#{key}`.") }
      end

      def enum_name(value, allowed, node, name)
        key = value.is_a?(Numeric) ? value.to_s : string_or_symbol(value, node, name)
        fail_at(node, "#{name.tr(' ', '_')}_value", "Unknown #{name} `#{key}`.") unless allowed.include?(key)
        key
      end

      def fail_at(node, code, message)
        raise RuntimeFailure.new(runtime_diagnostic(node, code, message))
      end

      def runtime_diagnostic(node, code, message)
        location = node.fetch("location", @program.fetch("location"))
        {
          source: "view",
          severity: "error",
          code: code,
          message: message.to_s.first(240),
          line: location.fetch("line"),
          column: location.fetch("column"),
          end_line: location.fetch("end_line"),
          end_column: location.fetch("end_column"),
          path: nil
        }
      end
    end
  end
end
