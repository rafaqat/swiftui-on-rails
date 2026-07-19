# frozen_string_literal: true

require "prism"
require "set"

module Showcase
  module Playground
    class SourceCompiler
      CompileResult = Struct.new(:program, :diagnostics, :node_count, keyword_init: true)

      # These compatibility shapes are derived from the versioned catalogue so
      # parsing, editor metadata, documentation, and LLM context cannot drift.
      BUILDERS = LanguageCatalog.builders.transform_values do |entry|
        arguments = entry.fetch("arguments")
        {
          positional: arguments.fetch("positional").length,
          keywords: arguments.fetch("keywords").keys,
          block: entry.dig("block", "mode") == "required"
        }.freeze
      end.freeze

      MODIFIERS = LanguageCatalog.modifiers.transform_values do |entry|
        arity = entry.dig("arguments", "arity")
        minimum = arity.fetch("minimum")
        maximum = arity.fetch("maximum")
        minimum == maximum ? minimum : (minimum..maximum)
      end.freeze

      BINARY_OPERATORS = LanguageCatalog.expressions.fetch("binary").fetch("operators")
      READ_OPERATIONS = LanguageCatalog.expressions.fetch("operation").fetch("operators")
      NUMBER_MAX_MAGNITUDE = LanguageCatalog.types.fetch("number").fetch("maximum_magnitude")
      INTEGER_MAX_MAGNITUDE = LanguageCatalog.types.fetch("integer").fetch("maximum_magnitude")

      def self.call(source)
        new(source).call
      end

      def initialize(source)
        @source = source.to_s
        @node_count = 0
      end

      def call
        validate_source!
        parsed = Prism.parse(@source)
        unless parsed.errors.empty?
          return CompileResult.new(program: nil, diagnostics: parsed.errors.first(Limits::DIAGNOSTICS).map { |error| syntax_diagnostic(error) }, node_count: 0)
        end

        count_nodes!(parsed.value)
        body = parsed.value.statements&.body || []
        fail_at(parsed.value, "root_view", "A playground must contain exactly one root view.") unless body.length == 1

        program = compile_statement(body.first, locals: Set.new([ "data" ]), depth: 1)
        fail_at(body.first, "root_view", "The root statement must be a view such as `vstack`.") unless program.fetch("type") == "view"

        document = IntermediateRepresentation.wrap(
          program,
          language_version: LanguageCatalog::VERSION
        )
        CompileResult.new(program: document, diagnostics: [], node_count: @node_count)
      rescue CompileFailure => error
        CompileResult.new(program: nil, diagnostics: [ error.diagnostic ], node_count: @node_count)
      end

      private

      CompileFailure = Class.new(StandardError) do
        attr_reader :diagnostic

        def initialize(diagnostic)
          @diagnostic = diagnostic
          super(diagnostic.fetch(:message))
        end
      end

      def validate_source!
        fail_at(nil, "source_size", "View source is limited to #{Limits::SOURCE_BYTES / 1024} KiB.") if @source.bytesize > Limits::SOURCE_BYTES
        fail_at(nil, "source_encoding", "View source must be valid UTF-8 without NUL bytes.") unless @source.valid_encoding? && !@source.include?("\0")

        lines = @source.lines
        fail_at(nil, "source_lines", "View source is limited to #{Limits::SOURCE_LINES} lines.") if lines.length > Limits::SOURCE_LINES
        long_line = lines.index { |line| line.bytesize > Limits::SOURCE_LINE_BYTES }
        fail_at(nil, "source_line_size", "Each source line is limited to #{Limits::SOURCE_LINE_BYTES / 1024} KiB.", line: long_line + 1) if long_line
      end

      def count_nodes!(root)
        stack = [ root ]
        until stack.empty?
          node = stack.pop
          next unless node.is_a?(Prism::Node)

          @node_count += 1
          fail_at(node, "ast_size", "View source contains more than #{Limits::AST_NODES} syntax nodes.") if @node_count > Limits::AST_NODES
          stack.concat(node.compact_child_nodes)
        end
      end

      def compile_statement(node, locals:, depth:)
        fail_at(node, "view_depth", "Views may be nested at most #{Limits::AST_DEPTH} levels.") if depth > Limits::AST_DEPTH

        case node
        when Prism::CallNode
          if node.receiver.nil? && node.name == :for_each
            compile_for_each(node, locals: locals, depth: depth)
          else
            compile_view(node, locals: locals, depth: depth)
          end
        when Prism::IfNode
          compile_if(node, locals: locals, depth: depth)
        when Prism::UnlessNode
          compile_unless(node, locals: locals, depth: depth)
        else
          fail_at(node, "unsupported_statement", "`#{node_label(node)}` is not available in the playground language.")
        end
      end

      def compile_view(node, locals:, depth:)
        modifiers = []
        cursor = node
        while cursor.is_a?(Prism::CallNode) && cursor.receiver && MODIFIERS.key?(cursor.name.to_s)
          fail_at(cursor, "modifier_block", "Modifiers cannot receive blocks.") if cursor.block
          modifiers.unshift(compile_modifier(cursor, locals: locals, depth: depth))
          cursor = cursor.receiver
        end

        fail_at(node, "modifier_count", "A view may use at most #{Limits::MODIFIERS_PER_VIEW} modifiers.") if modifiers.length > Limits::MODIFIERS_PER_VIEW
        unless cursor.is_a?(Prism::CallNode) && cursor.receiver.nil? && BUILDERS.key?(cursor.name.to_s)
          name = cursor.respond_to?(:name) ? cursor.name : node_label(cursor)
          fail_at(cursor, "unknown_view", "Unknown view or modifier `#{name}`.", hint: "Use a fixed playground view such as vstack, text, badge, or button.")
        end

        schema = BUILDERS.fetch(cursor.name.to_s)
        positional, keywords = compile_arguments(cursor, locals: locals, depth: depth)
        validate_call_shape!(cursor, positional, keywords, schema)
        validate_builder_block!(cursor, schema)

        children = schema.fetch(:block) ? compile_statements(cursor.block.body, locals: locals, depth: depth + 1) : []
        {
          "type" => "view",
          "name" => cursor.name.to_s,
          "arguments" => positional,
          "keywords" => keywords,
          "modifiers" => modifiers,
          "children" => children,
          "location" => location_hash(cursor)
        }
      end

      def compile_modifier(node, locals:, depth:)
        positional, keywords = compile_arguments(node, locals: locals, depth: depth)
        fail_at(node, "modifier_keywords", "Modifier `#{node.name}` does not accept keyword arguments.") unless keywords.empty?

        expected = MODIFIERS.fetch(node.name.to_s)
        valid = expected.is_a?(Range) ? expected.cover?(positional.length) : positional.length == expected
        fail_at(node, "modifier_arguments", "Modifier `#{node.name}` received the wrong number of arguments.") unless valid

        {
          "name" => node.name.to_s,
          "arguments" => positional,
          "location" => location_hash(node)
        }
      end

      def compile_for_each(node, locals:, depth:)
        positional, keywords = compile_arguments(node, locals: locals, depth: depth)
        unless positional.length == 1 && keywords.keys == [ "id" ] && node.block
          fail_at(node, "for_each_shape", "Use `for_each(collection, id: \"id\") do |item| ... end`.")
        end

        parameters = node.block.parameters&.parameters
        requireds = parameters&.requireds || []
        extras = parameters && [ parameters.optionals, parameters.posts, parameters.keywords, parameters.rest, parameters.keyword_rest, parameters.block ].compact.flatten
        unless requireds.length == 1 && extras.to_a.empty?
          fail_at(node.block, "for_each_parameter", "`for_each` requires exactly one simple loop variable.")
        end

        variable = requireds.first.name.to_s
        fail_at(requireds.first, "for_each_shadow", "Loop variable `#{variable}` shadows an existing name.") if locals.include?(variable)

        child_locals = locals.dup.add(variable)
        {
          "type" => "for_each",
          "collection" => positional.first,
          "id" => keywords.fetch("id"),
          "variable" => variable,
          "children" => compile_statements(node.block.body, locals: child_locals, depth: depth + 1),
          "location" => location_hash(node)
        }
      end

      def compile_if(node, locals:, depth:)
        {
          "type" => "if",
          "predicate" => compile_expression(node.predicate, locals: locals, depth: depth + 1),
          "then" => compile_statements(node.statements, locals: locals, depth: depth + 1),
          "else" => compile_subsequent(node.subsequent, locals: locals, depth: depth + 1),
          "location" => location_hash(node)
        }
      end

      def compile_unless(node, locals:, depth:)
        {
          "type" => "unless",
          "predicate" => compile_expression(node.predicate, locals: locals, depth: depth + 1),
          "then" => compile_statements(node.statements, locals: locals, depth: depth + 1),
          "else" => compile_subsequent(node.else_clause, locals: locals, depth: depth + 1),
          "location" => location_hash(node)
        }
      end

      def compile_subsequent(node, locals:, depth:)
        case node
        when nil
          []
        when Prism::ElseNode
          compile_statements(node.statements, locals: locals, depth: depth)
        when Prism::IfNode
          [ compile_if(node, locals: locals, depth: depth) ]
        else
          fail_at(node, "conditional_branch", "This conditional branch is not supported.")
        end
      end

      def compile_statements(node, locals:, depth:)
        body = node&.body || []
        body.map { |statement| compile_statement(statement, locals: locals, depth: depth) }
      end

      def compile_arguments(node, locals:, depth:)
        raw = node.arguments&.arguments || []
        keyword_node = raw.last if raw.last.is_a?(Prism::KeywordHashNode)
        raw = raw[0...-1] if keyword_node
        positional = raw.map { |argument| compile_expression(argument, locals: locals, depth: depth + 1) }
        keywords = {}

        keyword_node&.elements&.each do |element|
          unless element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
            fail_at(element, "keyword_shape", "Keyword splats and computed keyword names are not supported.")
          end
          key = element.key.unescaped.to_s
          fail_at(element, "duplicate_keyword", "Keyword `#{key}` is repeated.") if keywords.key?(key)
          keywords[key] = compile_expression(element.value, locals: locals, depth: depth + 1)
        end
        [ positional, keywords ]
      end

      def validate_call_shape!(node, positional, keywords, schema)
        unless positional.length == schema.fetch(:positional)
          fail_at(node, "view_arguments", "View `#{node.name}` received the wrong number of positional arguments.")
        end
        unknown = keywords.keys - schema.fetch(:keywords)
        fail_at(node, "unknown_keyword", "View `#{node.name}` does not accept `#{unknown.first}:`.") if unknown.any?
      end

      def validate_builder_block!(node, schema)
        if schema.fetch(:block)
          fail_at(node, "missing_view_block", "View `#{node.name}` requires a block.") unless node.block
          fail_at(node.block, "view_block_parameters", "View blocks cannot declare parameters.") if node.block.parameters
        elsif node.block
          fail_at(node, "unexpected_view_block", "View `#{node.name}` does not accept a block.")
        end
      end

      def compile_expression(node, locals:, depth:)
        fail_at(node, "expression_depth", "Expressions may be nested at most #{Limits::AST_DEPTH} levels.") if depth > Limits::AST_DEPTH

        case node
        when Prism::StringNode
          expression("literal", node, "value" => node.unescaped.to_s)
        when Prism::InterpolatedStringNode
          parts = node.parts.map do |part|
            if part.is_a?(Prism::StringNode)
              expression("literal", part, "value" => part.unescaped.to_s)
            elsif part.is_a?(Prism::EmbeddedStatementsNode)
              compile_embedded_expression(part, locals: locals, depth: depth + 1)
            else
              fail_at(part, "interpolation", "Only expressions are allowed inside interpolated strings.")
            end
          end
          expression("interpolation", node, "parts" => parts)
        when Prism::SymbolNode
          expression("symbol", node, "value" => node.unescaped.to_s)
        when Prism::IntegerNode
          if node.value.abs > INTEGER_MAX_MAGNITUDE
            fail_at(node, "number_range", "Integer literals are limited to ±#{INTEGER_MAX_MAGNITUDE}.")
          end
          expression("literal", node, "value" => node.value)
        when Prism::FloatNode
          unless node.value.finite? && node.value.abs <= NUMBER_MAX_MAGNITUDE
            fail_at(node, "number_range", "Number literals must be finite and bounded.")
          end
          expression("literal", node, "value" => node.value)
        when Prism::TrueNode
          expression("literal", node, "value" => true)
        when Prism::FalseNode
          expression("literal", node, "value" => false)
        when Prism::NilNode
          expression("literal", node, "value" => nil)
        when Prism::LocalVariableReadNode
          compile_variable(node.name.to_s, node, locals)
        when Prism::CallNode
          compile_call_expression(node, locals: locals, depth: depth)
        when Prism::AndNode
          expression("boolean", node, "operator" => "&&", "left" => compile_expression(node.left, locals: locals, depth: depth + 1), "right" => compile_expression(node.right, locals: locals, depth: depth + 1))
        when Prism::OrNode
          expression("boolean", node, "operator" => "||", "left" => compile_expression(node.left, locals: locals, depth: depth + 1), "right" => compile_expression(node.right, locals: locals, depth: depth + 1))
        when Prism::ParenthesesNode
          statements = node.body&.body || []
          fail_at(node, "parenthesized_expression", "Parentheses must contain one expression.") unless statements.length == 1
          compile_expression(statements.first, locals: locals, depth: depth + 1)
        else
          fail_at(node, "unsupported_expression", "`#{node_label(node)}` is not available in playground expressions.")
        end
      end

      def compile_embedded_expression(node, locals:, depth:)
        statements = node.statements&.body || []
        fail_at(node, "interpolation", "Interpolation must contain exactly one expression.") unless statements.length == 1
        compile_expression(statements.first, locals: locals, depth: depth)
      end

      def compile_call_expression(node, locals:, depth:)
        name = node.name.to_s
        arguments = node.arguments&.arguments || []
        fail_at(node, "expression_block", "Expression calls cannot receive blocks.") if node.block

        if node.receiver.nil? && arguments.empty?
          return compile_variable(name, node, locals)
        end

        if name == "[]" && node.receiver && arguments.length == 1
          return expression(
            "index",
            node,
            "receiver" => compile_expression(node.receiver, locals: locals, depth: depth + 1),
            "key" => compile_expression(arguments.first, locals: locals, depth: depth + 1)
          )
        end

        if node.receiver && READ_OPERATIONS.include?(name) && arguments.empty?
          return expression("operation", node, "operator" => name, "receiver" => compile_expression(node.receiver, locals: locals, depth: depth + 1))
        end

        if node.receiver && BINARY_OPERATORS.include?(name) && arguments.length == 1
          return expression(
            "binary",
            node,
            "operator" => name,
            "left" => compile_expression(node.receiver, locals: locals, depth: depth + 1),
            "right" => compile_expression(arguments.first, locals: locals, depth: depth + 1)
          )
        end

        if node.receiver && name == "!" && arguments.empty?
          return expression("not", node, "value" => compile_expression(node.receiver, locals: locals, depth: depth + 1))
        end

        fail_at(node, "unknown_expression", "Method `#{name}` is not available in playground expressions.")
      end

      def compile_variable(name, node, locals)
        fail_at(node, "unknown_variable", "Unknown data or loop variable `#{name}`.") unless locals.include?(name)
        expression("variable", node, "name" => name)
      end

      def expression(type, node, attributes = {})
        { "type" => type, "location" => location_hash(node) }.merge(attributes)
      end

      def syntax_diagnostic(error)
        location = error.location
        {
          source: "view",
          severity: "error",
          code: "syntax",
          message: error.message.to_s.first(240),
          line: location.start_line,
          column: location.start_column + 1,
          end_line: location.end_line,
          end_column: location.end_column + 1,
          path: nil
        }
      end

      def fail_at(node, code, message, line: nil, hint: nil)
        location = node ? location_hash(node) : { "line" => line || 1, "column" => 1, "end_line" => line || 1, "end_column" => 1 }
        raise CompileFailure.new({
          source: "view",
          severity: "error",
          code: code,
          message: message,
          line: location.fetch("line"),
          column: location.fetch("column"),
          end_line: location.fetch("end_line"),
          end_column: location.fetch("end_column"),
          path: nil,
          hint: hint
        }.compact)
      end

      def location_hash(node)
        location = node.location
        {
          "line" => location.start_line,
          "column" => location.start_column + 1,
          "end_line" => location.end_line,
          "end_column" => location.end_column + 1
        }
      end

      def node_label(node)
        node.class.name.delete_prefix("Prism::").delete_suffix("Node")
      end
    end
  end
end
