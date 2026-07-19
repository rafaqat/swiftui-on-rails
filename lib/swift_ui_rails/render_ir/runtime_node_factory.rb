# frozen_string_literal: true

module SwiftUIRails
  # Immutable resolved runtime view-tree support.
  module RenderIR
    # Internal initializer mixed into Node only for the runtime factory. Keeping
    # direct assignments here avoids reflective per-field allocation while the
    # public Node constructor remains the strict generic data boundary.
    module RuntimeNodeInitialization
      private

      def initialize_runtime_node( # rubocop:disable Metrics/ParameterLists
        kind:, props:, modifiers:, children:, identity:, accessibility:
      )
        @kind = kind
        @props = props
        @modifiers = immutable_runtime_records(modifiers, Modifier, '$.modifiers')
        @children = immutable_runtime_records(children, Node, '$.children')
        @identity = identity
        @accessibility = accessibility
        assign_attributes(
          {
            'accessibility' => accessibility,
            'children' => runtime_record_attributes(@children),
            'identity' => identity,
            'kind' => kind,
            'modifiers' => runtime_record_attributes(@modifiers),
            'props' => props
          }.freeze
        )
        freeze
      end

      def immutable_runtime_records(values, record_class, path)
        Structure.array!(values, path).each_with_index do |value, index|
          next if value.is_a?(record_class)

          raise InvalidStructure.new(
            "RenderIR runtime records must be #{record_class.name}.",
            path: "#{path}[#{index}]"
          )
        end
        values.empty? ? Node::EMPTY_ARRAY : values.dup.freeze
      end

      def runtime_record_attributes(records)
        records.empty? ? Node::EMPTY_ARRAY : records.map(&:to_h).freeze
      end
    end

    # Closed, allocation-conscious constructors for nodes emitted by the live
    # DSL lowerer. Caller-controlled leaves are normalized and the complete
    # document is still validated by HTMLRenderer before markup is emitted.
    module RuntimeNodeFactory
      module_function

      def text(value)
        build(
          kind: 'text_literal',
          props: { 'value' => Normalizer.call(value.to_s, path: '$.props.value') }.freeze
        )
      end

      def trusted_html(capability)
        build(
          kind: 'trusted_html',
          props: { 'capability' => Normalizer.call(capability, path: '$.props.capability') }.freeze
        )
      end

      def fragment(children)
        build(kind: 'fragment', children: children)
      end

      def element( # rubocop:disable Metrics/ParameterLists
        kind:,
        tag:,
        attribute_pairs:,
        paired:,
        modifiers: Node::EMPTY_ARRAY,
        children: Node::EMPTY_ARRAY,
        identity: nil,
        accessibility: Node::EMPTY_HASH
      )
        build(
          kind: Normalizer.call(kind, path: '$.kind'),
          props: element_props(tag, attribute_pairs, paired),
          modifiers: modifiers,
          children: children,
          identity: identity.nil? ? nil : Normalizer.call(identity, path: '$.identity'),
          accessibility: normalize_object(accessibility, '$.accessibility')
        )
      end

      def element_props(tag, attribute_pairs, paired)
        {
          'attribute_pairs' => normalize_array(attribute_pairs, '$.props.attribute_pairs'),
          'paired' => paired,
          'tag' => Normalizer.call(tag, path: '$.props.tag')
        }.freeze
      end
      private_class_method :element_props

      def normalize_array(value, path)
        return Node::EMPTY_ARRAY if value.empty?

        Normalizer.call(value, path: path)
      end
      private_class_method :normalize_array

      def normalize_object(value, path)
        return Node::EMPTY_HASH if value.empty?

        Normalizer.call(value, path: path)
      end
      private_class_method :normalize_object

      def build( # rubocop:disable Metrics/ParameterLists
        kind:,
        props: Node::EMPTY_HASH,
        modifiers: Node::EMPTY_ARRAY,
        children: Node::EMPTY_ARRAY,
        identity: nil,
        accessibility: Node::EMPTY_HASH
      )
        node = Node.allocate
        node.send(
          :initialize_runtime_node,
          kind: kind,
          props: props,
          modifiers: modifiers,
          children: children,
          identity: identity,
          accessibility: accessibility
        )
      end
      private_class_method :build
    end

    Node.include(RuntimeNodeInitialization)
  end
end
