# frozen_string_literal: true

require_relative '../render_ir/semantic_action_events'

module SwiftUIRails
  module Reactive
    # Host controllers include this concern to execute component-owned actions.
    # Every request must carry both the short-lived stream capability and the
    # encrypted component snapshot emitted by the rendered component root.
    module ComponentActionsController
      extend ActiveSupport::Concern
      include RenderPatchResponses

      SAFE_IDENTIFIER_PATTERN = /\A[A-Za-z][A-Za-z0-9_-]{0,127}\z/.freeze
      SAFE_COMPONENT_PATTERN = /\A(?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*Component\z/.freeze
      MAX_REQUEST_BYTES = 256.kilobytes
      MAX_EVENT_DETAIL_BYTES = 16.kilobytes
      MAX_EVENT_DETAIL_DEPTH = 4
      MAX_EVENT_DETAIL_ENTRIES = 64
      MAX_EVENT_DETAIL_KEY_BYTES = 128
      MAX_EVENT_DETAIL_STRING_BYTES = 2.kilobytes
      InvalidCapabilityError = Class.new(SwiftUIRails::SecurityError)

      included do
        before_action :verify_component_security, only: :create
        before_action :enforce_swift_ui_action_size_limit, only: :create
        before_action :check_swift_ui_action_rate_limit, only: :create
      end

      # Reject oversized payloads from the Content-Length header, before
      # `params` is ever touched — otherwise Rails parses the whole JSON body
      # into memory first, defeating the guard.
      def enforce_swift_ui_action_size_limit
        length = request.content_length
        return unless length && length > MAX_REQUEST_BYTES

        raise SwiftUIRails::SecurityError, "Action request is too large"
      end

      def create
        action_data = permitted_swift_ui_action
        validate_action_request!(action_data)

        component = resolve_swift_ui_storybook_component(action_data) if respond_to?(:resolve_swift_ui_storybook_component, true)
        component_snapshot = nil
        component, component_snapshot = restore_authorized_component(action_data) unless component

        render_component_for_actions(component)
        unless component.registered_actions.include?(action_data[:action_id])
          raise SwiftUIRails::SecurityError, "Unknown component action"
        end
        verify_issued_action!(component, component_snapshot, action_data[:action_id]) if component_snapshot

        component.execute_action(action_data[:action_id], action_data)
        if respond_to?(:persist_swift_ui_storybook_component, true)
          persist_swift_ui_storybook_component(component, action_data)
        end
        rendered = render_to_string(component)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(action_data[:component_id]) { rendered.html_safe }
          end
          format.json do
            render json: reactive_render_payload(
              component: component,
              snapshot: component_snapshot || {},
              rendered: rendered,
              requested_version: action_data[:render_patch_version]
            ).merge(
              success: true,
              component_id: action_data[:component_id]
            )
          end
        end
      rescue ReactiveComponentSnapshot::ReplayedSnapshotError => error
        audit_swift_ui_action_rejection(error, action_data)
        render_swift_ui_action_error("Component changed; refresh and try again", :conflict)
      rescue ReactiveComponentSnapshot::InvalidSnapshotError, InvalidCapabilityError => error
        audit_swift_ui_action_rejection(error, action_data)
        render_swift_ui_action_error("Action is not authorized", :forbidden)
      rescue SwiftUIRails::SecurityError, ArgumentError, TypeError => error
        audit_swift_ui_action_rejection(error, action_data)
        render_swift_ui_action_error("Action is not authorized", :unprocessable_entity)
      rescue StandardError => error
        Rails.logger.error "[SwiftUIRails] component action failed: #{error.class}"
        render_swift_ui_action_error("Action could not be completed", :unprocessable_entity)
      end

      private

      def permitted_swift_ui_action
        permitted = params.permit(
          :action_id,
          :component_id,
          :component_class,
          :event_type,
          :target_value,
          :target_checked,
          :snapshot_token,
          :stream_token,
          :render_patch_version,
          :story_session_id,
          :story_name,
          :story_variant,
          target_dataset: {}
        )
        if params.key?(:event_detail)
          permitted[:event_detail] = normalize_action_event_detail!(params[:event_detail])
        end
        permitted
      end

      def validate_action_request!(action_data)
        raise SwiftUIRails::SecurityError, "Action request is too large" if request.raw_post.bytesize > MAX_REQUEST_BYTES

        %i[action_id component_id].each do |name|
          value = action_data[name]
          unless value.is_a?(String) && value.match?(SAFE_IDENTIFIER_PATTERN)
            raise SwiftUIRails::SecurityError, "Invalid #{name}"
          end
        end

        component_class = action_data[:component_class]
        unless component_class.is_a?(String) && component_class.match?(SAFE_COMPONENT_PATTERN)
          raise SwiftUIRails::SecurityError, "Invalid component class"
        end

        event_type = action_data[:event_type]
        unless event_type.is_a?(String) && RenderIR::SemanticActionEvents.include?(event_type)
          raise SwiftUIRails::SecurityError, "Invalid action event"
        end
      end

      def normalize_action_event_detail!(raw_detail)
        detail = raw_detail.is_a?(ActionController::Parameters) ? raw_detail.to_unsafe_h : raw_detail
        unless detail.is_a?(Hash)
          raise SwiftUIRails::SecurityError, "Action event detail must be an object"
        end

        normalized = normalize_action_event_value!(detail, depth: 0, entries: [0])
        if JSON.generate(normalized).bytesize > MAX_EVENT_DETAIL_BYTES
          raise SwiftUIRails::SecurityError, "Action event detail is too large"
        end

        normalized
      end

      def normalize_action_event_value!(value, depth:, entries:)
        raise SwiftUIRails::SecurityError, "Action event detail is too deep" if depth > MAX_EVENT_DETAIL_DEPTH

        case value
        when ActionController::Parameters
          normalize_action_event_value!(value.to_unsafe_h, depth: depth, entries: entries)
        when Hash
          value.each_with_object({}) do |(raw_key, child), normalized|
            entries[0] += 1
            raise SwiftUIRails::SecurityError, "Action event detail has too many entries" if entries[0] > MAX_EVENT_DETAIL_ENTRIES

            key = raw_key.to_s
            invalid_key = key.length > MAX_EVENT_DETAIL_KEY_BYTES || key.match?(/[[:cntrl:]]/) ||
              %w[__proto__ constructor prototype].include?(key)
            raise SwiftUIRails::SecurityError, "Invalid action event detail key" if invalid_key

            normalized[key] = normalize_action_event_value!(child, depth: depth + 1, entries: entries)
          end
        when Array
          value.map do |child|
            entries[0] += 1
            raise SwiftUIRails::SecurityError, "Action event detail has too many entries" if entries[0] > MAX_EVENT_DETAIL_ENTRIES

            normalize_action_event_value!(child, depth: depth + 1, entries: entries)
          end
        when String
          if value.length > MAX_EVENT_DETAIL_STRING_BYTES
            raise SwiftUIRails::SecurityError, "Action event detail string is too large"
          end
          value.dup
        when Float
          raise SwiftUIRails::SecurityError, "Action event detail number must be finite" unless value.finite?

          value
        when Integer, TrueClass, FalseClass, NilClass
          value
        else
          raise SwiftUIRails::SecurityError, "Unsupported action event detail value"
        end
      end

      def restore_authorized_component(action_data)
        authorization_context = ReactiveAuthorizationContext.resolve(self)
        valid_stream = ReactiveStreamToken.valid_for?(
          action_data[:stream_token].to_s,
          action_data[:component_id].to_s,
          authorization_context: authorization_context
        )
        raise InvalidCapabilityError, "Invalid component capability" unless valid_stream

        snapshot = ReactiveComponentSnapshot.consume!(
          action_data[:snapshot_token].to_s,
          component_id: action_data[:component_id].to_s,
          component_class: action_data[:component_class].to_s,
          authorization_context: authorization_context
        )
        component_class = safe_constantize_component(action_data[:component_class])

        component = component_class.restore_reactive_snapshot(
          props: snapshot.fetch("props", {}),
          state: snapshot.fetch("state", {}),
          bindings: snapshot.fetch("bindings", {}),
          component_id: action_data[:component_id]
        )
        [component, snapshot]
      end

      def verify_issued_action!(component, snapshot, action_id)
        issued_descriptor = snapshot.fetch("actions", {})[action_id]
        current_descriptor = component.registered_action_descriptors[action_id]
        valid = issued_descriptor.is_a?(String) && current_descriptor.is_a?(String) &&
          ActiveSupport::SecurityUtils.secure_compare(issued_descriptor, current_descriptor)
        raise SwiftUIRails::SecurityError, "Component action changed since rendering" unless valid
      end

      def safe_constantize_component(component_class_name)
        unless ReactiveController.allowed_component_names.include?(component_class_name)
          raise SwiftUIRails::SecurityError, "Unauthorized component"
        end

        component_class = component_class_name.constantize
        valid_application_component = defined?(ApplicationComponent) && component_class < ApplicationComponent
        unless component_class < SwiftUIRails::Component::Base || valid_application_component
          raise SwiftUIRails::SecurityError, "Invalid component type"
        end

        component_class
      rescue NameError
        raise SwiftUIRails::SecurityError, "Unknown component"
      end

      def render_component_for_actions(component)
        # Register action blocks through the normal ViewComponent lifecycle.
        # Calling #call directly leaves #helpers unavailable, which breaks
        # production components that compose route, flash, or form helpers.
        render_to_string(component)
      end

      def verify_component_security
        return true if request.xhr? || request.format.turbo_stream?

        render json: { error: "Invalid request format" }, status: :bad_request
        false
      end

      def check_swift_ui_action_rate_limit
        count = Rails.cache.increment(
          "swift_ui_actions:#{request.remote_ip}",
          1,
          expires_in: 1.minute
        )
        return if count.nil? || count <= 120

        render json: { error: "Rate limit exceeded" }, status: :too_many_requests
      end

      def audit_swift_ui_action_rejection(error, action_data)
        details = {
          reason: error.message,
          component_class: action_data&.[](:component_class),
          component_id: action_data&.[](:component_id),
          ip_address: request.remote_ip
        }
        Rails.logger.warn "[SECURITY AUDIT] swift_ui_action_rejected: #{details.to_json}"
      end

      def render_swift_ui_action_error(message, status)
        respond_to do |format|
          format.turbo_stream { head status }
          format.json { render json: { error: message }, status: status }
          format.any { render json: { error: message }, status: status }
        end
      end
    end
  end
end
