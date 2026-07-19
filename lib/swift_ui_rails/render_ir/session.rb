# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Owns one lowering/render transaction and its non-serializable sidecar.
    class Session
      attr_reader :view_context, :capabilities

      def initialize(view_context:, profile: 'trusted')
        @view_context = view_context
        @profile = profile.to_s
        @capabilities = CapabilityRegistry.new
      end

      def trusted_html(value)
        RuntimeNodeFactory.trusted_html(capabilities.register(:trusted_html, value))
      end

      def text(value) # rubocop:disable Rails/Delegate
        RuntimeNodeFactory.text(value)
      end

      def document(children:, component: nil, language_version: nil)
        metadata = {}
        metadata['component'] = component.class.name.to_s if component
        metadata['capability_count'] = capabilities.count

        Document.new(
          root: RuntimeNodeFactory.fragment(children),
          profile: @profile,
          language_version: language_version,
          metadata: metadata
        )
      end

      def render(document)
        HTMLRenderer.call(document, view_context: view_context, capabilities: capabilities)
      end
    end
  end
end
