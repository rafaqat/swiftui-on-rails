# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # A resolved semantic view node, independent of its eventual HTML element.
    class Node < Record
      ALLOWED_KEYS = %w[accessibility children identity kind modifiers props].freeze
      REQUIRED_KEYS = %w[kind].freeze
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      attr_reader :kind, :props, :modifiers, :children, :identity, :accessibility

      def self.from_h(value = nil, path: '$', **attributes)
        value = keyword_hash(value, attributes)
        normalized = Normalizer.call(value, path: path)
        from_normalized(normalized, path: path)
      end

      # Internal fast path for a subtree normalized once by its parent.
      def self.from_normalized(value, path: '$')
        object = allocate
        object.send(:initialize_from_normalized, value, path)
        object
      end
      private_class_method :from_normalized

      def self.keyword_hash(value, attributes)
        return attributes if value.nil?
        return value if attributes.empty?

        raise ArgumentError, 'pass a RenderIR node as a hash or keyword fields, not both'
      end
      private_class_method :keyword_hash

      def initialize( # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
        kind:,
        props: EMPTY_HASH,
        modifiers: EMPTY_ARRAY,
        children: EMPTY_ARRAY,
        identity: nil,
        accessibility: EMPTY_HASH
      )
        super()
        @kind = Structure.plain_string!(Normalizer.call(kind, path: '$.kind'), '$.kind', field: 'node kind')
        @props = Structure.object!(Normalizer.call(props, path: '$.props'), '$.props')
        @accessibility = Structure.object!(
          Normalizer.call(accessibility, path: '$.accessibility'),
          '$.accessibility'
        )
        @identity = Normalizer.call(identity, path: '$.identity')
        @modifiers = Structure.array!(modifiers, '$.modifiers').each_with_index.map do |modifier, index|
          modifier.is_a?(Modifier) ? modifier : Modifier.from_h(modifier, path: "$.modifiers[#{index}]")
        end.freeze
        @children = Structure.array!(children, '$.children').each_with_index.map do |child, index|
          child.is_a?(Node) ? child : Node.from_h(child, path: "$.children[#{index}]")
        end.freeze
        assign_attributes(canonical_attributes)
        freeze
      end

      def each_node(&block)
        return enum_for(:each_node) unless block

        yield self
        children.each { |child| child.each_node(&block) }
        self
      end

      private

      def initialize_from_normalized(attributes, path)
        Structure.object!(attributes, path)
        Structure.keys!(attributes, allowed: ALLOWED_KEYS, required: REQUIRED_KEYS, path: path)

        assign_semantic_fields(attributes, path)
        assign_tree_fields(attributes, path)
        assign_attributes(canonical_attributes)
        freeze
      end

      def assign_semantic_fields(values, path)
        @kind = Structure.plain_string!(values.fetch('kind'), "#{path}.kind", field: 'node kind')
        @props = Structure.object!(values.fetch('props', EMPTY_HASH), "#{path}.props")
        @accessibility = Structure.object!(values.fetch('accessibility', EMPTY_HASH), "#{path}.accessibility")
        @identity = values.fetch('identity', nil)
      end

      def assign_tree_fields(values, path)
        @modifiers = wrap_modifiers(values.fetch('modifiers', EMPTY_ARRAY), path)
        @children = wrap_children(values.fetch('children', EMPTY_ARRAY), path)
      end

      def canonical_attributes
        {
          'accessibility' => accessibility,
          'children' => children.map(&:to_h).freeze,
          'identity' => identity,
          'kind' => kind,
          'modifiers' => modifiers.map(&:to_h).freeze,
          'props' => props
        }.freeze
      end

      def wrap_modifiers(values, path)
        Structure.array!(values, "#{path}.modifiers").each_with_index.map do |value, index|
          Modifier.send(:from_normalized, value, path: "#{path}.modifiers[#{index}]")
        end.freeze
      end

      def wrap_children(values, path)
        Structure.array!(values, "#{path}.children").each_with_index.map do |value, index|
          Node.send(:from_normalized, value, path: "#{path}.children[#{index}]")
        end.freeze
      end
    end
  end
end
