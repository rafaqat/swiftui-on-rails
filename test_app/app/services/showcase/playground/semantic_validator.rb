# frozen_string_literal: true

require "set"

module Showcase
  module Playground
    # Validates the meaning of compiled playground IR independently from both
    # Ruby syntax parsing and HTML rendering. Diagnostics deliberately speak in
    # view-language terms and include stable paths/fixes that an editor or LLM
    # can consume without interpreting a Ruby exception.
    class SemanticValidator
      IR = IntermediateRepresentation

      STATEMENT_TYPES = %w[view if unless for_each].freeze
      EXPRESSION_KEYS = {
        "literal" => %w[type value location],
        "symbol" => %w[type value location],
        "variable" => %w[type name location],
        "index" => %w[type receiver key location],
        "interpolation" => %w[type parts location],
        "boolean" => %w[type operator left right location],
        "not" => %w[type value location],
        "binary" => %w[type operator left right location],
        "operation" => %w[type operator receiver location]
      }.freeze
      STATEMENT_KEYS = {
        "view" => %w[type name arguments keywords modifiers children location],
        "for_each" => %w[type collection id variable children location],
        "if" => %w[type predicate then else location],
        "unless" => %w[type predicate then else location]
      }.freeze
      MODIFIER_KEYS = %w[name arguments location].freeze
      LOCATION_KEYS = %w[line column end_line end_column].freeze
      IDENTIFIER_PATTERN = LanguageCatalog.types.fetch("identifier_key").fetch("pattern")
      IDENTIFIER = Regexp.new("\\A(?:#{IDENTIFIER_PATTERN})\\z")
      VARIABLE = /\A[a-z_][a-zA-Z0-9_]*\z/
      BINARY_OPERATORS = LanguageCatalog.expressions.fetch("binary").fetch("operators").map(&:to_s).freeze
      BOOLEAN_OPERATORS = LanguageCatalog.expressions.fetch("boolean").fetch("operators").map(&:to_s).freeze
      READ_OPERATIONS = LanguageCatalog.expressions.fetch("operation").fetch("operators").map(&:to_s).freeze

      class ValidationResult
        attr_reader :document, :diagnostics

        def initialize(document:, diagnostics:)
          @document = document
          @diagnostics = diagnostics.freeze
          freeze
        end

        def success?
          diagnostics.none? { |diagnostic| diagnostic.fetch(:severity) == "error" }
        end

        def program
          document&.program
        end
      end

      class << self
        def call(value = nil, program: nil, document: nil, catalog: nil)
          target = document || program || value
          new(target, catalog: catalog).call
        end

        def default_catalog
          Showcase::Playground.const_get(:LanguageCatalog)
        rescue NameError
          LegacyCatalog
        end
      end

      def initialize(value, catalog: nil)
        @value = value
        @catalog = CatalogAdapter.new(catalog || self.class.default_catalog)
        @diagnostics = []
      end

      def call
        document = IR::Document.wrap(@value, language_version: @catalog.version)
        validate_document(document)
        ValidationResult.new(document: document, diagnostics: deep_freeze(@diagnostics))
      rescue IR::InvalidValue => error
        add_diagnostic(
          nil,
          path: error.path,
          code: "ir_value",
          message: error.message,
          hint: "Use only JSON objects, arrays, strings, finite numbers, booleans, and null in compiled IR."
        )
        ValidationResult.new(document: nil, diagnostics: deep_freeze(@diagnostics))
      end

      private

      def validate_document(document)
        validate_document_keys(document)

        unless document.schema == IR::SCHEMA
          add_diagnostic(
            nil,
            path: "$.schema",
            code: "ir_schema",
            message: "This document is not SwiftUI Rails playground IR.",
            hint: "Set `schema` to `#{IR::SCHEMA}`.",
            fix: replace_fix("$.schema", IR::SCHEMA)
          )
        end

        unless IR::SUPPORTED_VERSIONS.include?(document.version)
          add_diagnostic(
            nil,
            path: "$.version",
            code: "ir_version",
            message: "Playground IR version `#{document.version.inspect}` is not supported.",
            hint: "Compile the view with IR version #{IR::VERSION}.",
            fix: replace_fix("$.version", IR::VERSION)
          )
        end

        if document.language_version.nil?
          add_diagnostic(
            nil,
            path: "$.language_version",
            code: "language_version_missing",
            message: "Playground IR must declare its language catalogue version.",
            hint: "Recompile the DSL against language catalogue #{@catalog.version}.",
            fix: add_fix("$.language_version", @catalog.version)
          )
        elsif @catalog.version && document.language_version != @catalog.version
          add_diagnostic(
            nil,
            path: "$.language_version",
            code: "language_version",
            message: "The program targets language catalog #{document.language_version}, but this runtime provides #{@catalog.version}.",
            hint: "Recompile the DSL against the current language catalog before rendering."
          )
        end

        validate_statement(document.root, path: "$.root", parent: nil, scopes: Set.new([ "data" ]), root: true)
      end

      def validate_document_keys(document)
        allowed = %w[schema version language_version root]
        unknown_keys(document.attributes, allowed, path: "$").each do |key|
          add_unknown_field(document.root, key, path: "$.#{key}")
        end
        return if document.attributes.key?("root")

        add_diagnostic(
          nil,
          path: "$.root",
          code: "root_missing",
          message: "A playground IR document requires one root view.",
          hint: "Add the compiled view as the document's `root`."
        )
      end

      def validate_statement(node, path:, parent:, scopes:, root: false)
        unless node.raw.is_a?(Hash)
          return add_diagnostic(
            node,
            path: path,
            code: "node_shape",
            message: "A view-tree node must be an object, not #{json_type(node.raw)}.",
            hint: "Replace this value with a view, conditional, or `for_each` node."
          )
        end

        type = node.type
        unless STATEMENT_TYPES.include?(type) && @catalog.statement?(type)
          return add_diagnostic(
            node,
            path: "#{path}.type",
            code: "node_type",
            message: "Unknown view-tree node type `#{type}`.",
            hint: "Use one of: #{supported_statement_types.join(', ')}."
          )
        end

        if root && type != "view"
          add_diagnostic(
            node,
            path: path,
            code: "root_view",
            message: "A playground must start with one view, not `#{type}`.",
            hint: "Wrap this statement in `vstack do ... end`."
          )
        end

        validate_location(node, path: "#{path}.location") if node.key?("location")

        case type
        when "view"
          validate_view(node, path: path, parent: parent, scopes: scopes)
        when "for_each"
          validate_for_each(node, path: path, parent: parent, scopes: scopes)
        when "if", "unless"
          validate_conditional(node, path: path, parent: parent, scopes: scopes)
        end
      end

      def validate_view(node, path:, parent:, scopes:)
        validate_node_keys(node, path: path)
        name = node.name
        builder = name.is_a?(String) ? @catalog.builder(name) : nil

        unless name.is_a?(String) && !name.empty?
          add_diagnostic(node, path: "#{path}.name", code: "view_name", message: "Every view node needs a builder name.")
        end

        unless builder
          add_diagnostic(
            node,
            path: "#{path}.name",
            code: "unknown_view",
            message: "`#{name}` is not in this playground's view vocabulary.",
            hint: "Use one of: #{@catalog.builder_names.first(12).join(', ')}."
          )
        else
          validate_legal_parent(node, builder, parent: parent, path: path)
        end

        arguments = node["arguments"]
        keywords = node["keywords"]
        modifiers = node["modifiers"]
        children = node["children"]

        validate_expression_array(arguments, path: "#{path}.arguments", scopes: scopes)
        validate_keyword_expressions(keywords, path: "#{path}.keywords", scopes: scopes)
        validate_call_shape(node, builder, arguments: arguments, keywords: keywords, path: path) if builder
        validate_modifiers(node, modifiers, builder: builder, path: "#{path}.modifiers", scopes: scopes)

        unless children.is_a?(Array)
          add_diagnostic(node, path: "#{path}.children", code: "children_shape", message: "View children must be an ordered list.")
          return
        end

        if builder && !builder_allows_children?(builder) && children.any?
          add_diagnostic(
            node,
            path: "#{path}.children",
            code: "leaf_children",
            message: "`#{name}` is a leaf view and cannot contain child views.",
            hint: "Move these children into a stack or remove them.",
            fix: replace_fix("#{path}.children", [])
          )
        end

        node.children.each_with_index do |child, index|
          validate_statement(child, path: "#{path}.children[#{index}]", parent: node, scopes: scopes)
        end
      end

      def validate_for_each(node, path:, parent:, scopes:)
        validate_node_keys(node, path: path)
        validate_statement_parent(node, parent: parent, path: path)

        if node.collection
          validate_expression(node.collection, path: "#{path}.collection", scopes: scopes)
        else
          add_diagnostic(node, path: "#{path}.collection", code: "for_each_collection", message: "`for_each` requires a collection expression.")
        end

        variable = node.variable
        unless variable.is_a?(String) && VARIABLE.match?(variable)
          add_diagnostic(
            node,
            path: "#{path}.variable",
            code: "for_each_variable",
            message: "`for_each` needs one lowercase loop variable.",
            hint: "Use a name such as `item` or `product`."
          )
        end
        if scopes.include?(variable)
          add_diagnostic(
            node,
            path: "#{path}.variable",
            code: "for_each_shadow",
            message: "Loop variable `#{variable}` would hide an existing value.",
            hint: "Choose a distinct loop variable name."
          )
        end

        validate_for_each_identity(node, path: path, scopes: scopes)

        children = node["children"]
        unless children.is_a?(Array)
          add_diagnostic(node, path: "#{path}.children", code: "children_shape", message: "`for_each` children must be an ordered list.")
          return
        end

        child_scopes = variable.is_a?(String) ? scopes.dup.add(variable) : scopes
        node.children.each_with_index do |child, index|
          validate_statement(child, path: "#{path}.children[#{index}]", parent: node, scopes: child_scopes)
        end
      end

      def validate_for_each_identity(node, path:, scopes:)
        identity_path = "#{path}.id"
        unless node.identity
          return add_diagnostic(
            node,
            path: identity_path,
            code: "for_each_identity_missing",
            message: "`for_each` requires an explicit stable identity key.",
            hint: "Use `id: \"id\"` and give every item a unique `id` value.",
            fix: add_fix(identity_path, literal_expression("id"))
          )
        end

        validate_expression(node.identity, path: identity_path, scopes: scopes)
        raw = node.identity.attributes
        unless node.identity.type == "literal" && raw["value"].is_a?(String)
          return add_diagnostic(
            node.identity,
            path: identity_path,
            code: "for_each_identity_literal",
            message: "A collection identity must be a literal JSON key, so it stays stable across renders.",
            hint: "Use `id: \"id\"` rather than a computed expression.",
            fix: replace_fix(identity_path, literal_expression("id"))
          )
        end

        key = raw["value"]
        return if IDENTIFIER.match?(key)

        add_diagnostic(
          node.identity,
          path: identity_path,
          code: "for_each_identity_key",
          message: "`#{key}` is not a safe stable identity key.",
          hint: "Identity keys may contain letters, numbers, underscores, and hyphens, and cannot start with a number.",
          fix: replace_fix(identity_path, literal_expression("id"))
        )
      end

      def validate_conditional(node, path:, parent:, scopes:)
        validate_node_keys(node, path: path)
        validate_statement_parent(node, parent: parent, path: path)

        if node.predicate
          validate_expression(node.predicate, path: "#{path}.predicate", scopes: scopes)
        else
          add_diagnostic(node, path: "#{path}.predicate", code: "predicate_missing", message: "`#{node.type}` requires a predicate.")
        end

        { "then" => node.then_children, "else" => node.else_children }.each do |branch, wrapped_children|
          raw_children = node[branch]
          unless raw_children.is_a?(Array)
            add_diagnostic(node, path: "#{path}.#{branch}", code: "branch_shape", message: "The `#{branch}` branch must be an ordered list of views.")
            next
          end

          wrapped_children.each_with_index do |child, index|
            validate_statement(child, path: "#{path}.#{branch}[#{index}]", parent: node, scopes: scopes)
          end
        end
      end

      def validate_statement_parent(node, parent:, path:)
        return unless parent.nil?

        add_diagnostic(
          node,
          path: path,
          code: "statement_parent",
          message: "`#{node.type}` cannot be the root view.",
          hint: "Place it inside a container such as `vstack`."
        )
      end

      def validate_legal_parent(node, builder, parent:, path:)
        legal_parents = catalog_array(builder, "legal_parents")
        return if legal_parents.empty? || legal_parents.include?("*")

        actual = parent_contexts(parent)
        return if (legal_parents & actual).any?

        description = parent ? "inside `#{parent_label(parent)}`" : "at the document root"
        add_diagnostic(
          node,
          path: path,
          code: "illegal_parent",
          message: "`#{node.name}` cannot appear #{description}.",
          hint: "Allowed contexts: #{legal_parents.join(', ')}."
        )
      end

      def validate_call_shape(node, entry, arguments:, keywords:, path:)
        return unless arguments.is_a?(Array) && keywords.is_a?(Hash)

        minimum, maximum = positional_bounds(entry)
        unless arguments.length >= minimum && (maximum.nil? || arguments.length <= maximum)
          expected = minimum == maximum ? minimum.to_s : "#{minimum}..#{maximum || 'many'}"
          add_diagnostic(
            node,
            path: "#{path}.arguments",
            code: "view_arguments",
            message: "`#{node.name}` expects #{expected} positional argument(s), but received #{arguments.length}."
          )
        end

        keyword_specs = catalog_hash(argument_schema(entry)["keywords"])
        unknown = keywords.keys - keyword_specs.keys
        unknown.each do |keyword|
          keyword_path = "#{path}.keywords.#{keyword}"
          add_diagnostic(
            node,
            path: keyword_path,
            code: "unknown_keyword",
            message: "`#{node.name}` does not accept `#{keyword}:`.",
            hint: keyword_specs.empty? ? "Remove this keyword." : "Available keywords: #{keyword_specs.keys.join(', ')}.",
            fix: remove_fix(keyword_path)
          )
        end

        keyword_specs.each do |keyword, spec|
          next unless required_argument?(spec) && !keywords.key?(keyword)

          add_diagnostic(
            node,
            path: "#{path}.keywords.#{keyword}",
            code: "missing_keyword",
            message: "`#{node.name}` requires `#{keyword}:`."
          )
        end

        validate_declared_arguments(
          entry,
          arguments: arguments,
          keywords: keywords,
          path: path,
          owner: node.name
        )
      end

      def validate_modifiers(node, raw_modifiers, builder:, path:, scopes:)
        unless raw_modifiers.is_a?(Array)
          add_diagnostic(node, path: path, code: "modifiers_shape", message: "View modifiers must be an ordered list.")
          return
        end

        node.modifiers.each_with_index do |modifier, index|
          modifier_path = "#{path}[#{index}]"
          unless modifier.raw.is_a?(Hash)
            add_diagnostic(modifier, path: modifier_path, code: "modifier_shape", message: "A modifier must be an object.")
            next
          end

          unknown_keys(modifier.attributes, MODIFIER_KEYS, path: modifier_path).each do |key|
            add_unknown_field(modifier, key, path: "#{modifier_path}.#{key}")
          end
          validate_location(modifier, path: "#{modifier_path}.location") if modifier.key?("location")

          name = modifier.name
          entry = name.is_a?(String) ? @catalog.modifier(name) : nil
          unless entry
            add_diagnostic(
              modifier,
              path: "#{modifier_path}.name",
              code: "unknown_modifier",
              message: "`#{name}` is not in this playground's modifier vocabulary.",
              hint: "Use one of: #{@catalog.modifier_names.first(12).join(', ')}."
            )
            next
          end

          validate_modifier_target(modifier, entry, view: node, builder: builder, path: modifier_path)
          arguments = modifier["arguments"]
          validate_expression_array(arguments, path: "#{modifier_path}.arguments", scopes: scopes)
          if arguments.is_a?(Array)
            validate_modifier_arity(modifier, entry, arguments: arguments, path: modifier_path)
            validate_declared_arguments(
              entry,
              arguments: arguments,
              keywords: {},
              path: modifier_path,
              owner: modifier.name,
              modifier: true
            )
          end
        end
      end

      def validate_modifier_target(modifier, entry, view:, builder:, path:)
        legal_targets = catalog_array(entry, "legal_targets", "targets", "legal_builders")
        builder_targets = catalog_array(builder, "legal_modifiers", "allowed_modifiers") if builder
        compatible = legal_targets.empty? || legal_targets.include?("*") || legal_targets.include?(view.name)
        compatible &&= builder_targets.empty? || builder_targets.include?("*") || builder_targets.include?(modifier.name) if builder_targets
        return if compatible

        add_diagnostic(
          modifier,
          path: path,
          code: "modifier_incompatible",
          message: "`.#{modifier.name}` cannot modify `#{view.name}`.",
          hint: legal_targets.empty? ? "Remove this modifier." : "Use it with: #{legal_targets.join(', ')}.",
          fix: remove_fix(path)
        )
      end

      def validate_modifier_arity(modifier, entry, arguments:, path:)
        minimum, maximum = positional_bounds(entry)
        return if arguments.length >= minimum && (maximum.nil? || arguments.length <= maximum)

        expected = minimum == maximum ? minimum.to_s : "#{minimum}..#{maximum || 'many'}"
        add_diagnostic(
          modifier,
          path: "#{path}.arguments",
          code: "modifier_arguments",
          message: "`.#{modifier.name}` expects #{expected} argument(s), but received #{arguments.length}."
        )
      end

      def validate_declared_arguments(entry, arguments:, keywords:, path:, owner:, modifier: false)
        schema = argument_schema(entry)
        positional_specs = schema["positional"]
        if positional_specs.is_a?(Array)
          arguments.each_with_index do |raw, index|
            spec = positional_spec_at(positional_specs, index)
            next unless spec

            details = catalog_hash(spec)
            label = modifier && details["name"] == "value" ? owner : (details["name"] || "argument #{index + 1}")
            validate_declared_argument(
              raw,
              details,
              path: "#{path}.arguments[#{index}]",
              label: label
            )
          end
        end

        keyword_specs = catalog_hash(schema["keywords"])
        keywords.each do |keyword, raw|
          spec = keyword_specs[keyword]
          next unless spec

          validate_declared_argument(
            raw,
            catalog_hash(spec),
            path: "#{path}.keywords.#{keyword}",
            label: keyword
          )
        end
      end

      def positional_spec_at(specs, index)
        return specs[index] if index < specs.length

        rest = specs.last
        catalog_hash(rest)["rest"] == true ? rest : nil
      end

      def validate_declared_argument(raw, spec, path:, label:)
        type_name = spec["type"].to_s
        definition = @catalog.type(type_name)
        return unless definition

        expression = IR::Expression.wrap(raw, normalized: true)
        known, value, input_form = static_argument_value(expression)
        return unless known
        return if nullable_argument?(value, spec)

        valid = validate_declared_type(
          expression,
          value,
          input_form,
          type_name: type_name,
          definition: definition,
          spec: spec,
          path: path,
          label: label
        )
        return unless valid && value.is_a?(Numeric)

        validate_argument_bounds(
          expression,
          value,
          type_name: type_name,
          definition: definition,
          spec: spec,
          path: path,
          label: label
        )
      end

      def static_argument_value(expression)
        case expression.type
        when "literal"
          return [ false, nil, nil ] unless expression.key?("value")

          value = expression["value"]
          return [ false, nil, nil ] if value.is_a?(Array) || value.is_a?(Hash)

          [ true, value, literal_input_form(value) ]
        when "symbol"
          value = expression["value"]
          value.is_a?(String) ? [ true, value, "symbol" ] : [ false, nil, nil ]
        else
          # Variables, indexes, operations, and interpolations are checked by
          # the bounded renderer because their values depend on fixture data.
          [ false, nil, nil ]
        end
      end

      def literal_input_form(value)
        case value
        when String then "string"
        when Integer then "integer"
        when Float then "float"
        when TrueClass, FalseClass then "boolean"
        when NilClass then "nil"
        end
      end

      def nullable_argument?(value, spec)
        value.nil? && spec["required"] != true && spec.key?("default") && spec["default"].nil?
      end

      def validate_declared_type(expression, value, input_form, type_name:, definition:, spec:, path:, label:)
        constraints = definition.merge(spec)
        kind = definition["kind"]

        case kind
        when "expression", "condition"
          true
        when "scalar"
          validate_scalar_type(expression, value, input_form, constraints, type_name: type_name, path: path, label: label)
        when "primitive"
          validate_primitive_type(expression, value, constraints, type_name: type_name, path: path, label: label)
        when "number"
          validate_number_type(expression, value, integer: false, type_name: type_name, definition: definition, spec: spec, path: path, label: label)
        when "integer"
          validate_number_type(expression, value, integer: true, type_name: type_name, definition: definition, spec: spec, path: path, label: label)
        when "string"
          validate_string_type(expression, value, input_form, constraints, type_name: type_name, definition: definition, spec: spec, path: path, label: label)
        when "enum"
          validate_enum_type(expression, value, input_form, constraints, type_name: type_name, definition: definition, spec: spec, path: path, label: label)
        when "patterned_enum"
          validate_patterned_enum_type(expression, value, input_form, constraints, type_name: type_name, definition: definition, spec: spec, path: path, label: label)
        else
          true
        end
      end

      def validate_scalar_type(expression, value, input_form, constraints, type_name:, path:, label:)
        allowed = Array(constraints["values"]).map(&:to_s)
        valid_type = allowed.empty? || allowed.include?(input_form)

        unless valid_type
          add_argument_diagnostic(
            expression,
            path: path,
            code: "#{diagnostic_token(label)}_type",
            message: "`#{label}` must be scalar text, not #{json_type(value)}.",
            hint: "Use a string, number, boolean, symbol, or nil value.",
            replacement: literal_expression("")
          )
          return false
        end

        if constraints["non_empty"] && (value.nil? || value.to_s.strip.empty?)
          replacement = constraints["default"]
          replacement = "Action" unless replacement.is_a?(String) && !replacement.strip.empty?
          add_argument_diagnostic(
            expression,
            path: path,
            code: "#{diagnostic_token(label)}_required",
            message: "`#{label}` must provide a non-empty accessible name.",
            hint: "Use a concise visible label that names the control's action.",
            replacement: literal_expression(replacement)
          )
          return false
        end

        true
      end

      def validate_primitive_type(expression, value, constraints, type_name:, path:, label:)
        allowed = Array(constraints["values"])
        return true if allowed.include?(value)

        default = constraints["default"]
        replacement = allowed.include?(default) ? default : (allowed.first.nil? ? false : allowed.first)
        add_argument_diagnostic(
          expression,
          path: path,
          code: "#{diagnostic_token(label)}_type",
          message: "`#{label}` must be true or false.",
          hint: "Replace this value with a boolean literal.",
          replacement: literal_expression(replacement)
        )
        false
      end

      def validate_number_type(expression, value, integer:, type_name:, definition:, spec:, path:, label:)
        valid = integer ? value.is_a?(Integer) : value.is_a?(Numeric)
        return true if valid

        replacement = numeric_replacement(value, definition.merge(spec), integer: integer)
        expected = integer ? "an integer" : "a finite number"
        add_argument_diagnostic(
          expression,
          path: path,
          code: "#{diagnostic_token(label)}_type",
          message: "`#{label}` must be #{expected}.",
          hint: "Use a numeric literal or a fixture expression that resolves to #{expected}.",
          replacement: literal_expression(replacement)
        )
        false
      end

      def validate_string_type(expression, value, input_form, constraints, type_name:, definition:, spec:, path:, label:)
        unless input_form == "string"
          add_argument_diagnostic(
            expression,
            path: path,
            code: string_diagnostic_code(type_name, label),
            message: "`#{label}` must be a string.",
            hint: string_hint(type_name, constraints),
            replacement: literal_expression(string_replacement(type_name, definition, spec))
          )
          return false
        end

        maximum = constraints["max_bytes"]
        minimum = constraints["min_bytes"]
        pattern = constraints["pattern"]
        valid_length = (!maximum || value.bytesize <= maximum) && (!minimum || value.bytesize >= minimum)
        valid_pattern = !pattern || catalog_pattern_match?(pattern, value)
        return true if valid_length && valid_pattern

        add_argument_diagnostic(
          expression,
          path: path,
          code: string_diagnostic_code(type_name, label),
          message: string_error_message(value, label, pattern: pattern, minimum: minimum, maximum: maximum),
          hint: string_hint(type_name, constraints),
          replacement: literal_expression(string_replacement(type_name, definition, spec))
        )
        false
      rescue RegexpError
        true
      end

      def validate_enum_type(expression, value, input_form, constraints, type_name:, definition:, spec:, path:, label:)
        allowed_forms = Array(constraints["input_forms"]).map(&:to_s)
        allowed_values = Array(constraints["values"]).map(&:to_s)
        normalized = value.to_s
        return true if allowed_forms.include?(input_form) && allowed_values.include?(normalized)

        replacement = allowed_values.first.to_s
        add_argument_diagnostic(
          expression,
          path: path,
          code: "#{diagnostic_token(type_name)}_value",
          message: "Unknown #{human_catalog_name(type_name)} `#{value}`.",
          hint: "Use one of: #{allowed_values.first(16).join(', ')}.",
          replacement: replacement_expression(replacement, preferred_form: input_form, definition: definition)
        )
        false
      end

      def validate_patterned_enum_type(expression, value, input_form, constraints, type_name:, definition:, spec:, path:, label:)
        allowed_forms = Array(constraints["input_forms"]).map(&:to_s)
        valid = allowed_forms.include?(input_form) && patterned_value?(value.to_s, constraints["forms"])
        return true if valid

        replacement = patterned_replacement(constraints["forms"])
        add_argument_diagnostic(
          expression,
          path: path,
          code: type_name == "safe_color" ? "color_value" : "#{diagnostic_token(type_name)}_value",
          message: "Unknown #{human_catalog_name(type_name)} `#{value}`.",
          hint: type_name == "safe_color" ? "Use an allowlisted name such as `slate-600`, or prefer a semantic foreground/background style." : "Use a value declared by the language catalogue.",
          replacement: replacement_expression(replacement, preferred_form: input_form, definition: definition)
        )
        false
      end

      def validate_argument_bounds(expression, value, type_name:, definition:, spec:, path:, label:)
        constraints = definition.merge(spec)
        minimum = constraints["minimum"] || constraints["min"]
        maximum = constraints["maximum"] || constraints["max"]
        minimum_exclusive = constraints["minimum_exclusive"]
        maximum_exclusive = constraints["maximum_exclusive"]
        below = (minimum && value < minimum) || (minimum_exclusive && value <= minimum_exclusive)
        above = (maximum && value > maximum) || (maximum_exclusive && value >= maximum_exclusive)
        return true unless below || above

        integer = definition["kind"] == "integer"
        replacement = numeric_replacement(value, constraints, integer: integer)
        range = range_description(minimum, maximum, minimum_exclusive, maximum_exclusive)
        add_argument_diagnostic(
          expression,
          path: path,
          code: "#{diagnostic_token(label)}_range",
          message: "`#{label}` must be #{range}.",
          hint: "Replace the literal with a value inside the catalogue's bounded range.",
          replacement: literal_expression(replacement)
        )
        false
      end

      def patterned_value?(value, forms)
        Array(forms).any? do |form|
          details = catalog_hash(form)
          names = Array(details["name_values"]).map(&:to_s)
          shades = Array(details["shade_values"]).map(&:to_s)
          if details["template"] == "{name}"
            names.include?(value)
          elsif details["template"] == "{name}-{shade}"
            name, shade, extra = value.split("-", 3)
            extra.nil? && names.include?(name) && shades.include?(shade)
          else
            false
          end
        end
      end

      def patterned_replacement(forms)
        form = Array(forms).map { |entry| catalog_hash(entry) }.find { |entry| Array(entry["name_values"]).any? }
        return "primary" unless form

        name = Array(form["name_values"]).first.to_s
        shade = Array(form["shade_values"]).first
        shade ? "#{name}-#{shade}" : name
      end

      def numeric_replacement(value, constraints, integer:)
        candidate = constraints["default"]
        candidate = value if candidate.nil? && value.is_a?(Numeric)
        candidate = constraints["minimum"] || constraints["min"] || 0 if candidate.nil? || !candidate.is_a?(Numeric)

        minimum = constraints["minimum"] || constraints["min"]
        maximum = constraints["maximum"] || constraints["max"]
        candidate = [ candidate, minimum ].max if minimum
        candidate = [ candidate, maximum ].min if maximum

        if (exclusive = constraints["minimum_exclusive"]) && candidate <= exclusive
          candidate = valid_numeric_default(constraints, lower: exclusive) || exclusive + (integer ? 1 : 1.0)
        end
        if (exclusive = constraints["maximum_exclusive"]) && candidate >= exclusive
          candidate = valid_numeric_default(constraints, upper: exclusive) || exclusive - (integer ? 1 : 1.0)
        end
        integer ? candidate.to_i : candidate
      end

      def valid_numeric_default(constraints, lower: nil, upper: nil)
        value = constraints["default"]
        return unless value.is_a?(Numeric)
        return if lower && value <= lower
        return if upper && value >= upper

        value
      end

      def range_description(minimum, maximum, minimum_exclusive, maximum_exclusive)
        return "greater than #{minimum_exclusive} and less than #{maximum_exclusive}" if minimum_exclusive && maximum_exclusive
        return "greater than #{minimum_exclusive} and at most #{maximum}" if minimum_exclusive && maximum
        return "at least #{minimum} and less than #{maximum_exclusive}" if minimum && maximum_exclusive
        return "from #{minimum} through #{maximum}" if minimum && maximum
        return "greater than #{minimum_exclusive}" if minimum_exclusive
        return "at least #{minimum}" if minimum
        return "less than #{maximum_exclusive}" if maximum_exclusive

        "at most #{maximum}"
      end

      def string_diagnostic_code(_type_name, label)
        "#{diagnostic_token(label)}_value"
      end

      def string_error_message(value, label, pattern:, minimum:, maximum:)
        return "`#{label}` is longer than #{maximum} bytes." if maximum && value.bytesize > maximum
        return "`#{label}` is shorter than #{minimum} bytes." if minimum && value.bytesize < minimum

        "`#{label}` value `#{value}` does not match the required safe format."
      end

      def string_hint(_type_name, constraints)
        pattern = constraints["pattern"]
        pattern ? "Use a string matching `#{pattern}`." : "Use a bounded string literal."
      end

      def string_replacement(type_name, definition, spec)
        value = spec["default"]
        return value if value.is_a?(String) && string_value_matches?(value, definition.merge(spec))
        return "id" if type_name == "identifier_key"

        "value"
      end

      def string_value_matches?(value, constraints)
        return false if constraints["max_bytes"] && value.bytesize > constraints["max_bytes"]
        return false if constraints["min_bytes"] && value.bytesize < constraints["min_bytes"]

        !constraints["pattern"] || catalog_pattern_match?(constraints["pattern"], value)
      rescue RegexpError
        true
      end

      def catalog_pattern_match?(pattern, value)
        match = Regexp.new(pattern).match(value)
        match && match.begin(0).zero? && match.end(0) == value.length
      end

      def replacement_expression(value, preferred_form:, definition:)
        if preferred_form == "symbol" && Array(definition["input_forms"]).map(&:to_s).include?("symbol") && value.is_a?(String)
          { "type" => "symbol", "value" => value }.freeze
        else
          literal_expression(value)
        end
      end

      def add_argument_diagnostic(expression, path:, code:, message:, hint:, replacement:)
        add_diagnostic(
          expression,
          path: path,
          code: code,
          message: message,
          hint: hint,
          fix: replace_fix(path, replacement)
        )
      end

      def diagnostic_token(value)
        value.to_s.tr(" ", "_").gsub(/[^a-zA-Z0-9_]/, "").downcase
      end

      def human_catalog_name(value)
        value.to_s.tr("_", " ")
      end

      def validate_expression_array(value, path:, scopes:)
        unless value.is_a?(Array)
          add_diagnostic(nil, path: path, code: "arguments_shape", message: "Arguments must be an ordered list of expressions.")
          return
        end

        value.each_with_index do |raw, index|
          validate_expression(IR::Expression.wrap(raw, normalized: true), path: "#{path}[#{index}]", scopes: scopes)
        end
      end

      def validate_keyword_expressions(value, path:, scopes:)
        unless value.is_a?(Hash)
          add_diagnostic(nil, path: path, code: "keywords_shape", message: "Keyword arguments must be an object.")
          return
        end

        value.each do |key, raw|
          validate_expression(IR::Expression.wrap(raw, normalized: true), path: "#{path}.#{key}", scopes: scopes)
        end
      end

      def validate_expression(expression, path:, scopes:)
        unless expression.raw.is_a?(Hash)
          return add_diagnostic(
            expression,
            path: path,
            code: "expression_shape",
            message: "A DSL value must be a typed expression, not #{json_type(expression.raw)}."
          )
        end

        type = expression.type
        unless IR::Expression::TYPES.include?(type) && @catalog.expression?(type)
          return add_diagnostic(
            expression,
            path: "#{path}.type",
            code: "expression_type",
            message: "Unknown expression type `#{type}`.",
            hint: "Use one of: #{supported_expression_types.join(', ')}."
          )
        end

        unknown_keys(expression.attributes, EXPRESSION_KEYS.fetch(type), path: path).each do |key|
          add_unknown_field(expression, key, path: "#{path}.#{key}")
        end
        validate_location(expression, path: "#{path}.location") if expression.key?("location")

        case type
        when "literal"
          validate_literal(expression, path: path)
        when "symbol"
          unless expression["value"].is_a?(String) && !expression["value"].empty?
            add_diagnostic(expression, path: "#{path}.value", code: "symbol_value", message: "A symbol expression requires a non-empty name.")
          end
        when "variable"
          name = expression["name"]
          unless name.is_a?(String) && scopes.include?(name)
            add_diagnostic(
              expression,
              path: "#{path}.name",
              code: "unknown_variable",
              message: "Variable `#{name}` is not available in this scope.",
              hint: "Available values: #{scopes.to_a.sort.join(', ')}."
            )
          end
        when "index"
          validate_child_expression(expression, "receiver", path: path, scopes: scopes)
          validate_child_expression(expression, "key", path: path, scopes: scopes)
        when "interpolation"
          validate_expression_array(expression["parts"], path: "#{path}.parts", scopes: scopes)
        when "boolean"
          validate_operator(expression, BOOLEAN_OPERATORS, path: path)
          validate_child_expression(expression, "left", path: path, scopes: scopes)
          validate_child_expression(expression, "right", path: path, scopes: scopes)
        when "not"
          validate_child_expression(expression, "value", path: path, scopes: scopes)
        when "binary"
          validate_operator(expression, BINARY_OPERATORS, path: path)
          validate_child_expression(expression, "left", path: path, scopes: scopes)
          validate_child_expression(expression, "right", path: path, scopes: scopes)
        when "operation"
          validate_operator(expression, READ_OPERATIONS, path: path)
          validate_child_expression(expression, "receiver", path: path, scopes: scopes)
        end
      end

      def validate_literal(expression, path:)
        unless expression.key?("value")
          return add_diagnostic(expression, path: "#{path}.value", code: "literal_value", message: "A literal expression requires a value, including explicit null.")
        end

        value = expression["value"]
        return if value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value == true || value == false || value.nil?

        add_diagnostic(expression, path: "#{path}.value", code: "literal_type", message: "Literal values must be JSON scalars, not collections.")
      end

      def validate_child_expression(expression, key, path:, scopes:)
        raw = expression[key]
        unless raw.is_a?(Hash)
          return add_diagnostic(expression, path: "#{path}.#{key}", code: "expression_missing", message: "`#{expression.type}` requires a `#{key}` expression.")
        end

        validate_expression(IR::Expression.wrap(raw, normalized: true), path: "#{path}.#{key}", scopes: scopes)
      end

      def validate_operator(expression, allowed, path:)
        operator = expression["operator"]
        return if allowed.include?(operator)

        add_diagnostic(
          expression,
          path: "#{path}.operator",
          code: "operator",
          message: "`#{operator}` is not valid for a `#{expression.type}` expression.",
          hint: "Use one of: #{allowed.join(', ')}."
        )
      end

      def validate_location(record, path:)
        raw = record["location"]
        unless raw.is_a?(Hash)
          return add_diagnostic(record, path: path, code: "location_shape", message: "Source location metadata must be an object.")
        end

        unknown_keys(raw, LOCATION_KEYS, path: path).each do |key|
          add_unknown_field(record, key, path: "#{path}.#{key}")
        end
        valid = LOCATION_KEYS.all? { |key| raw[key].is_a?(Integer) && raw[key] >= 1 }
        return if valid && raw["end_line"] >= raw["line"]

        add_diagnostic(record, path: path, code: "location_value", message: "Source locations require positive start and end coordinates.")
      end

      def validate_node_keys(node, path:)
        unknown_keys(node.attributes, STATEMENT_KEYS.fetch(node.type), path: path).each do |key|
          add_unknown_field(node, key, path: "#{path}.#{key}")
        end
      end

      def unknown_keys(attributes, allowed, path:)
        return [] unless attributes.is_a?(Hash)

        attributes.keys - allowed
      end

      def add_unknown_field(record, key, path:)
        add_diagnostic(
          record,
          path: path,
          code: "unknown_ir_field",
          message: "`#{key}` is not part of this IR version.",
          hint: "Remove the field or compile against a newer supported schema.",
          fix: remove_fix(path)
        )
      end

      def argument_schema(entry)
        catalog_hash(entry["arguments"])
      end

      def positional_bounds(entry)
        raw = argument_schema(entry)["positional"]
        case raw
        when Integer
          [ raw, raw ]
        when Array
          rest = raw.any? { |spec| catalog_hash(spec)["rest"] == true }
          minimum = raw.count { |spec| required_argument?(spec) && catalog_hash(spec)["rest"] != true }
          maximum = rest ? nil : raw.length
          [ minimum, maximum ]
        when Hash
          minimum = raw.fetch("min", raw.fetch("minimum", 0))
          maximum = raw["max"] || raw["maximum"]
          [ minimum.to_i, maximum&.to_i ]
        else
          arity = entry["arity"]
          arity.is_a?(Integer) ? [ arity, arity ] : [ 0, 0 ]
        end
      end

      def required_argument?(spec)
        details = catalog_hash(spec)
        return true if details.empty?
        return details["required"] if details.key?("required")

        !details["optional"] && !details.key?("default")
      end

      def catalog_array(entry, *keys)
        return [] unless entry

        keys.each do |key|
          value = entry[key]
          return value.map(&:to_s) if value.is_a?(Array)
          return [ value.to_s ] if value.is_a?(String) || value.is_a?(Symbol)
        end
        []
      end

      def catalog_hash(value)
        return {} unless value.is_a?(Hash)

        value.to_h { |key, child| [ key.to_s, child ] }
      end

      def parent_contexts(parent)
        case parent
        when nil then [ "$root", "root" ]
        when IR::View then [ "container", "view", parent.name.to_s ]
        when IR::Conditional then [ "conditional", parent.type.to_s ]
        when IR::ForEach then [ "collection", "for_each" ]
        else []
        end
      end

      def parent_label(parent)
        parent.is_a?(IR::View) ? parent.name : parent.type
      end

      def supported_statement_types
        STATEMENT_TYPES.select { |type| @catalog.statement?(type) }
      end

      def supported_expression_types
        IR::Expression::TYPES.select { |type| @catalog.expression?(type) }
      end

      def builder_allows_children?(entry)
        block = entry["block"]
        return block.fetch("mode", "forbidden") != "forbidden" if block.is_a?(Hash)

        block == true || block.to_s == "required"
      end

      def literal_expression(value)
        { "type" => "literal", "value" => value }.freeze
      end

      def replace_fix(path, value)
        { kind: "replace", path: path, value: value }
      end

      def add_fix(path, value)
        { kind: "add", path: path, value: value }
      end

      def remove_fix(path)
        { kind: "remove", path: path }
      end

      def add_diagnostic(record, path:, code:, message:, hint: nil, fix: nil, severity: "error")
        return if @diagnostics.length >= diagnostic_limit

        location = diagnostic_location(record)
        @diagnostics << {
          source: "view",
          severity: severity,
          code: code,
          message: message.to_s.first(240),
          line: location.fetch("line", 1),
          column: location.fetch("column", 1),
          end_line: location.fetch("end_line", location.fetch("line", 1)),
          end_column: location.fetch("end_column", location.fetch("column", 1)),
          path: path,
          hint: hint,
          fix: fix
        }.compact
      end

      def diagnostic_location(record)
        return {} unless record.respond_to?(:attributes)

        location = record.attributes["location"]
        location.is_a?(Hash) ? location : {}
      end

      def diagnostic_limit
        Limits::DIAGNOSTICS
      rescue NameError
        50
      end

      def json_type(value)
        case value
        when Hash then "object"
        when Array then "array"
        when String then "string"
        when Numeric then "number"
        when TrueClass, FalseClass then "boolean"
        when NilClass then "null"
        else value.class.to_s
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| key.freeze; deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end

      # Compatibility fallback for isolated use before LanguageCatalog loads.
      # Production integration resolves the catalog constant through Zeitwerk.
      module LegacyCatalog
        VERSION = "legacy"
        module_function

        def builder(name)
          schema = SourceCompiler::BUILDERS[name.to_s]
          return unless schema

          {
            "arguments" => {
              "positional" => Array.new(schema.fetch(:positional)) { { "required" => true } },
              "keywords" => schema.fetch(:keywords).to_h { |keyword| [ keyword, { "required" => false } ] }
            },
            "block" => schema.fetch(:block),
            "legal_parents" => [ "$root", "container", "conditional", "collection" ]
          }
        end

        def modifier(name)
          arity = SourceCompiler::MODIFIERS[name.to_s]
          return unless arity

          positional = if arity.is_a?(Range)
            { "min" => arity.begin, "max" => arity.end }
          else
            arity
          end
          { "arguments" => { "positional" => positional, "keywords" => {} }, "legal_targets" => [ "*" ] }
        end

        def builders
          SourceCompiler::BUILDERS
        end

        def modifiers
          SourceCompiler::MODIFIERS
        end

        def statements
          STATEMENT_TYPES.to_h { |type| [ type, {} ] }
        end

        def expressions
          IR::Expression::TYPES.to_h { |type| [ type, {} ] }
        end
      end

      class CatalogAdapter
        def initialize(catalog)
          @catalog = catalog
        end

        def version
          return @catalog::VERSION.to_s if @catalog.is_a?(Module) && @catalog.const_defined?(:VERSION, false)
          return @catalog.version.to_s if @catalog.respond_to?(:version)

          nil
        end

        def builder(name)
          fetch_entry(:builder, :builders, name)
        end

        def modifier(name)
          fetch_entry(:modifier, :modifiers, name)
        end

        def type(name)
          fetch_entry(:type, :types, name)
        end

        def builder_names
          collection_keys(:builders)
        end

        def modifier_names
          collection_keys(:modifiers)
        end

        def statement?(name)
          return true if name.to_s == "view"

          catalog_membership(:statements, name, STATEMENT_TYPES)
        end

        def expression?(name)
          return true unless @catalog.respond_to?(:expressions)

          expressions = @catalog.public_send(:expressions)
          keys = expressions.respond_to?(:keys) ? expressions.keys.map(&:to_s) : Array(expressions).map(&:to_s)
          return true if keys.include?(name.to_s)

          categories = {
            "literal" => %w[literals],
            "symbol" => %w[literals],
            "interpolation" => %w[literals],
            "variable" => %w[variables],
            "index" => %w[index],
            "boolean" => %w[boolean],
            "not" => %w[boolean],
            "binary" => %w[comparison arithmetic],
            "operation" => %w[read_operations]
          }.fetch(name.to_s, [])
          (categories & keys).any?
        end

        private

        def fetch_entry(single_method, collection_method, name)
          value = @catalog.public_send(single_method, name.to_s) if @catalog.respond_to?(single_method)
          value ||= fetch_from_collection(collection_method, name)
          stringify_hash(value)
        rescue KeyError, ArgumentError
          nil
        end

        def fetch_from_collection(method, name)
          return unless @catalog.respond_to?(method)

          collection = @catalog.public_send(method)
          return unless collection.is_a?(Hash)

          collection[name.to_s] || collection[name.to_sym]
        end

        def collection_keys(method)
          return [] unless @catalog.respond_to?(method)

          collection = @catalog.public_send(method)
          collection.respond_to?(:keys) ? collection.keys.map(&:to_s).sort : Array(collection).map(&:to_s).sort
        end

        def catalog_membership(method, name, fallback)
          return fallback.include?(name) unless @catalog.respond_to?(method)

          collection = @catalog.public_send(method)
          keys = collection.respond_to?(:keys) ? collection.keys : Array(collection)
          keys.map(&:to_s).include?(name.to_s)
        end

        def stringify_hash(value)
          return unless value.is_a?(Hash)

          value.to_h { |key, child| [ key.to_s, child ] }
        end
      end
    end
  end
end
