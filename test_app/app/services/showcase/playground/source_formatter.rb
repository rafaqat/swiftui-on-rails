# frozen_string_literal: true

module Showcase
  module Playground
    # Produces one stable textual representation of a valid playground program.
    # Source is compiled through the allowlisted SourceCompiler first; this class
    # never evaluates Ruby and only serializes the compiler's immutable IR.
    class SourceFormatter
      FormatResult = Struct.new(:source, :diagnostics, :changed, keyword_init: true) do
        def success?
          diagnostics.empty?
        end

        def as_json(*)
          {
            ok: success?,
            source: source,
            diagnostics: diagnostics,
            changed: changed
          }
        end
      end

      class << self
        def call(source)
          new(source).call
        end
      end

      def initialize(source)
        @source = source.to_s
      end

      def call
        compilation = SourceCompiler.call(@source)
        return failure(compilation.diagnostics) if compilation.diagnostics.any?

        validation = SemanticValidator.call(compilation.program)
        return failure(validation.diagnostics) unless validation.success?

        canonical_source = "#{emit_statement(validation.program, 0)}\n"
        verification = SourceCompiler.call(canonical_source)
        return failure(formatter_diagnostic("canonical_source_invalid", "The canonical source did not pass validation.")) if verification.diagnostics.any?

        verification_validation = SemanticValidator.call(verification.program)
        unless verification_validation.success? && verification_validation.document.semantic_json == validation.document.semantic_json
          return failure(formatter_diagnostic("canonical_semantics_changed", "Formatting changed the compiled view semantics."))
        end

        FormatResult.new(
          source: canonical_source.freeze,
          diagnostics: [].freeze,
          changed: canonical_source != normalized_input
        ).freeze
      rescue KeyError, TypeError, ArgumentError => error
        failure(formatter_diagnostic("unsupported_ir", "The compiled view could not be formatted: #{error.message.to_s.first(160)}"))
      end

      private

      def emit_statement(node, depth)
        case node.fetch("type")
        when "view"
          emit_view(node, depth)
        when "for_each"
          emit_for_each(node, depth)
        when "if", "unless"
          emit_conditional(node, depth)
        else
          raise ArgumentError, "unknown statement type #{node['type'].inspect}"
        end
      end

      def emit_view(node, depth)
        prefix = indent(depth)
        arguments = node.fetch("arguments").map { |argument| emit_expression(argument) }
        arguments.concat(node.fetch("keywords").map { |name, value| "#{name}: #{emit_expression(value)}" })

        call = +node.fetch("name")
        call << "(#{arguments.join(', ')})" if arguments.any?

        source = if node.fetch("children").any? || block_builder?(node)
          lines = [ "#{prefix}#{call} do" ]
          node.fetch("children").each { |child| lines << emit_statement(child, depth + 1) }
          lines << "#{prefix}end"
          lines.join("\n")
        else
          "#{prefix}#{call}"
        end

        node.fetch("modifiers").each do |modifier|
          values = modifier.fetch("arguments").map { |argument| emit_expression(argument) }
          suffix = values.empty? ? "" : "(#{values.join(', ')})"
          source << "\n#{indent(depth + 1)}.#{modifier.fetch('name')}#{suffix}"
        end
        source
      end

      def emit_for_each(node, depth)
        lines = [
          "#{indent(depth)}for_each(#{emit_expression(node.fetch('collection'))}, id: #{emit_expression(node.fetch('id'))}) do |#{node.fetch('variable')}|"
        ]
        node.fetch("children").each { |child| lines << emit_statement(child, depth + 1) }
        lines << "#{indent(depth)}end"
        lines.join("\n")
      end

      def emit_conditional(node, depth)
        lines = [ "#{indent(depth)}#{node.fetch('type')} #{emit_expression(node.fetch('predicate'))}" ]
        node.fetch("then").each { |child| lines << emit_statement(child, depth + 1) }

        unless node.fetch("else").empty?
          lines << "#{indent(depth)}else"
          node.fetch("else").each { |child| lines << emit_statement(child, depth + 1) }
        end

        lines << "#{indent(depth)}end"
        lines.join("\n")
      end

      def emit_expression(expression)
        case expression.fetch("type")
        when "literal"
          emit_literal(expression.fetch("value"))
        when "symbol"
          expression.fetch("value").to_sym.inspect
        when "variable"
          expression.fetch("name")
        when "index"
          "#{emit_receiver(expression.fetch('receiver'))}[#{emit_expression(expression.fetch('key'))}]"
        when "operation"
          "#{emit_receiver(expression.fetch('receiver'))}.#{expression.fetch('operator')}"
        when "binary", "boolean"
          "(#{emit_expression(expression.fetch('left'))} #{expression.fetch('operator')} #{emit_expression(expression.fetch('right'))})"
        when "not"
          "!(#{emit_expression(expression.fetch('value'))})"
        when "interpolation"
          emit_interpolation(expression.fetch("parts"))
        else
          raise ArgumentError, "unknown expression type #{expression['type'].inspect}"
        end
      end

      def emit_receiver(expression)
        if %w[variable index operation].include?(expression.fetch("type"))
          emit_expression(expression)
        else
          "(#{emit_expression(expression)})"
        end
      end

      def emit_literal(value)
        case value
        when String then value.dump
        when Integer, Float then value.inspect
        when true then "true"
        when false then "false"
        when nil then "nil"
        else
          raise TypeError, "unsupported literal #{value.class}"
        end
      end

      def emit_interpolation(parts)
        body = parts.map do |part|
          if part.fetch("type") == "literal" && part.fetch("value").is_a?(String)
            part.fetch("value").dump[1...-1]
          else
            "\#{#{emit_expression(part)}}"
          end
        end.join
        %Q("#{body}")
      end

      def block_builder?(node)
        SourceCompiler::BUILDERS.fetch(node.fetch("name")).fetch(:block)
      end

      def normalized_input
        @source.end_with?("\n") ? @source : "#{@source}\n"
      end

      def indent(depth)
        "  " * depth
      end

      def failure(diagnostics)
        FormatResult.new(source: nil, diagnostics: Array(diagnostics).freeze, changed: false).freeze
      end

      def formatter_diagnostic(code, message)
        [ {
          source: "view",
          severity: "error",
          code: code,
          message: message,
          line: 1,
          column: 1,
          end_line: 1,
          end_column: 1,
          path: nil
        }.freeze ].freeze
      end
    end
  end
end
