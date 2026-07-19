# frozen_string_literal: true

require_relative 'attribute_policy'

module SwiftUIRails
  module RenderIR
    # Domain validation for resolved trees. Core records validate shape and
    # JSON safety; this validator enforces the executable renderer contract.
    class Validator
      PROFILES = %w[portable trusted].freeze
      KIND_PATTERN = /\A[a-z][a-z0-9_]*\z/

      def self.validate!(document, capabilities: nil)
        new(document, capabilities: capabilities).validate!
      end

      def initialize(document, capabilities: nil)
        @document = document
        @capabilities = capabilities
        @attribute_policy = AttributePolicy.new(profile: document.profile) if document.is_a?(Document)
      end

      def validate!
        raise InvalidStructure, 'RenderIR renderer requires a Document.' unless @document.is_a?(Document)
        unless PROFILES.include?(@document.profile)
          raise InvalidStructure.new(
            "RenderIR profile must be one of #{PROFILES.join(', ')}.",
            path: '$.profile'
          )
        end
        unless @document.root.kind == 'fragment'
          raise InvalidStructure.new(
            'Resolved RenderIR requires a fragment root.',
            path: '$.root.kind'
          )
        end

        validate_node!(@document.root, '$.root')
        @document
      end

      private

      def validate_node!(node, path)
        unless KIND_PATTERN.match?(node.kind)
          raise InvalidStructure.new('RenderIR node kind is invalid.', path: "#{path}.kind")
        end

        case node.kind
        when 'fragment'
          require_empty_props!(node, path)
        when 'text_literal'
          validate_text!(node, path)
        when 'trusted_html'
          validate_trusted_html!(node, path)
        else
          @attribute_policy.validate!(node, path)
        end

        node.children.each_with_index do |child, index|
          validate_node!(child, "#{path}.children[#{index}]")
        end
      end

      def require_empty_props!(node, path)
        return if node.props.empty?

        raise InvalidStructure.new('RenderIR fragment props must be empty.', path: "#{path}.props")
      end

      def validate_text!(node, path)
        unless node.props.keys == ['value'] && node.props.fetch('value').instance_of?(String)
          raise InvalidStructure.new(
            'RenderIR text_literal requires one string value.',
            path: "#{path}.props"
          )
        end
        return if node.children.empty?

        raise InvalidStructure.new('RenderIR text_literal cannot have children.', path: "#{path}.children")
      end

      def validate_trusted_html!(node, path)
        validate_trusted_profile!(path)
        validate_trusted_shape!(node, path)
        return unless @capabilities
        return if @capabilities.include?(node.props.fetch('capability'), kind: :trusted_html)

        raise CapabilityRegistry::MissingCapability.new(
          'RenderIR trusted HTML capability is not available in this render.',
          path: "#{path}.props.capability"
        )
      end

      def validate_trusted_profile!(path)
        return if @document.profile == 'trusted'

        raise InvalidStructure.new(
          'Portable RenderIR cannot contain trusted_html capabilities.',
          path: "#{path}.kind"
        )
      end

      def validate_trusted_shape!(node, path)
        valid_props = node.props.keys == ['capability'] && node.props.fetch('capability').instance_of?(String)
        unless valid_props
          raise InvalidStructure.new(
            'RenderIR trusted_html requires one capability identifier.',
            path: "#{path}.props"
          )
        end
        return if node.children.empty?

        raise InvalidStructure.new('RenderIR trusted_html cannot have children.', path: "#{path}.children")
      end
    end
  end
end
