# frozen_string_literal: true

require_relative 'patch_locator'

module SwiftUIRails
  module RenderIR
    # Deterministic ActionView backend for resolved RenderIR. It never executes
    # component Ruby or DSL blocks; lowering has already completed.
    class HTMLRenderer
      def self.call(document, view_context:, capabilities: CapabilityRegistry.new)
        new(document, view_context: view_context, capabilities: capabilities).call
      end

      def initialize(document, view_context:, capabilities:)
        @document = document
        @view_context = view_context
        @capabilities = capabilities
        @patch_locators = {}.freeze
      end

      def call
        Validator.validate!(@document, capabilities: @capabilities)
        @patch_locators = PatchLocator.for(@document)
        render_node(@document.root)
      end

      private

      def render_node(node)
        case node.kind
        when 'fragment'
          safe_join(node.children.map { |child| render_node(child) })
        when 'text_literal'
          ERB::Util.html_escape(node.props.fetch('value'))
        when 'trusted_html'
          render_trusted_html(node)
        else
          render_element(node)
        end
      end

      def render_element(node)
        tag_name = node.props.fetch('tag')
        options = decoded_attributes(node.props.fetch('attribute_pairs'))
        options = with_patch_locator(node, options)
        content = render_children(node.children)

        if node.props.fetch('paired') || node.children.any?
          @view_context.content_tag(tag_name, content, options)
        else
          @view_context.tag(tag_name, options)
        end
      end

      def decoded_attributes(attribute_pairs)
        return if attribute_pairs.empty?

        attribute_pairs.to_h.transform_values { |value| ValueCodec.decode(value) }
      end

      def with_patch_locator(node, options)
        patch_locator = @patch_locators[node]
        return options unless patch_locator

        (options || {}).merge(PatchLocator::ATTRIBUTE => patch_locator)
      end

      def render_children(children)
        return '' if children.empty?
        return render_node(children.first) if children.one?

        safe_join(children.map { |child| render_node(child) })
      end

      def render_trusted_html(node)
        value = @capabilities.fetch(node.props.fetch('capability'), kind: :trusted_html)
        return value if value.respond_to?(:html_safe?) && value.html_safe?

        ERB::Util.html_escape(value.to_s)
      end

      def safe_join(parts)
        if @view_context.respond_to?(:safe_join)
          @view_context.safe_join(parts)
        else
          ActionController::Base.helpers.safe_join(parts)
        end
      end
    end
  end
end
