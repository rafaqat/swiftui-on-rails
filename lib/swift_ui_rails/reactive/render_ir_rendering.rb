# frozen_string_literal: true

module SwiftUIRails
  module Reactive
    # Builds and renders the stable reactive root through resolved RenderIR.
    # Already-rendered safe buffers are supported only as a compatibility
    # boundary; live components pass their semantic child nodes directly.
    module RenderIRRendering # rubocop:disable Metrics/ModuleLength
      private

      # Compatibility entry point for callers that used Rendering directly.
      def wrap_with_reactive_container(content, component_id, stream_token = nil)
        build_reactive_container(content, component_id, stream_token)
      end

      def build_reactive_container(content, component_id, stream_token = nil)
        session = SwiftUIRails::RenderIR::Session.new(view_context: reactive_render_view_context)
        child = if content.is_a?(SwiftUIRails::RenderIR::Node)
                  content
                elsif content.respond_to?(:html_safe?) && content.html_safe?
                  session.trusted_html(content)
                else
                  session.text(content)
                end
        root = build_reactive_container_node([child], component_id, stream_token)
        document = session.document(children: [root], component: self)
        rendered = session.render(document)
        record_render_ir(document, rendered_html: rendered, session: session) if respond_to?(:record_render_ir)
        rendered
      end

      # Emits one framework-neutral semantic root. The browser runtime is a
      # protocol interpreter, not an application controller: all application
      # behavior remains in registered Ruby actions and RenderIR.
      def build_reactive_container_node(children, component_id, stream_token = nil)
        attributes = reactive_container_attributes(component_id, stream_token)

        SwiftUIRails::RenderIR::Node.new(
          kind: 'reactive_container',
          props: {
            tag: 'div',
            attribute_pairs: encoded_reactive_attributes(attributes),
            paired: true
          },
          children: children,
          identity: SwiftUIRails::RenderIR::ValueCodec.encode(component_id, path: '$.identity')
        )
      end

      def encoded_reactive_attributes(attributes)
        attributes.map.with_index do |(name, value), index|
          [
            name,
            SwiftUIRails::RenderIR::ValueCodec.encode(
              value,
              path: "$.props.attribute_pairs[#{index}][1]"
            )
          ]
        end
      end

      def reactive_container_attributes(component_id, stream_token)
        issue_reactive_tokens(component_id, stream_token)

        {
          'id' => component_id,
          'data-sui-root' => '1',
          'data-sui-id' => component_id,
          'data-sui-component' => self.class.name.to_s,
          'data-sui-stream' => @reactive_stream_token,
          'data-sui-snapshot' => @reactive_snapshot_token,
          'data-sui-update-url' => update_url_for_component,
          'data-sui-observed-stores' => observed_store_names.to_json
        }
      end

      def issue_reactive_tokens(component_id, stream_token)
        authorization_context = ReactiveAuthorizationContext.resolve(self)
        @reactive_patch_baseline_token = SwiftUIRails::RenderIR::PatchBaseline.issue
        @reactive_stream_token = stream_token || ReactiveStreamToken.generate(
          component_id,
          authorization_context: authorization_context
        )
        @reactive_snapshot_token = ReactiveComponentSnapshot.generate(
          self,
          component_id: component_id,
          authorization_context: authorization_context
        )
      end

      # Render patches are an optimization layered on the validated HTML
      # contract. A cache failure, an unpatchable trusted capability, or an
      # oversized tree simply leaves no baseline and forces the next response
      # down the full-HTML path.
      def store_reactive_patch_baseline(document, rendered_html:)
        token = @reactive_patch_baseline_token
        return if token.blank? || rendered_html.blank?

        tree = SwiftUIRails::RenderIR::PatchTree.build(document: document, html: rendered_html.to_s)
        return unless tree

        authorization_context = ReactiveAuthorizationContext.resolve(self)
        stored = SwiftUIRails::RenderIR::PatchBaseline.store(
          token: token,
          tree: tree,
          component_id: component_id,
          component_class: self.class.name.to_s,
          authorization_context: authorization_context
        )
        log_reactive_patch_baseline(token, stored: stored)
        @reactive_patch_tree = tree
      rescue StandardError => e
        Rails.logger.warn("[SwiftUIRails] render patch baseline unavailable: #{e.class}")
        @reactive_patch_tree = nil
      end

      def log_reactive_patch_baseline(token, stored:)
        message = if stored
                    fingerprint = Digest::SHA256.hexdigest(token).first(12)
                    "[SwiftUIRails] render patch baseline stored: #{fingerprint}"
                  else
                    '[SwiftUIRails] render patch fallback: baseline_cache_write_failed'
                  end
        Rails.logger.debug { message }
      end

      def reactive_render_view_context
        context = send(:view_context) if respond_to?(:view_context, true)
        context || ActionController::Base.helpers
      rescue StandardError
        ActionController::Base.helpers
      end

      def update_url_for_component
        '/swift_ui/components/update'
      end
    end
  end
end
