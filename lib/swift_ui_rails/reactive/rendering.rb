# frozen_string_literal: true

require_relative 'render_ir_rendering'

module SwiftUIRails
  module Reactive
    # Binds browser capabilities to the request that rendered them. The
    # default uses the Rails session and current_user when available;
    # applications can supply a tenant-aware proc through configuration.
    module ReactiveAuthorizationContext
      module_function

      def resolve(subject)
        default_scope = resolve_default(subject)
        hook = SwiftUIRails.configuration.reactive_authorization_context
        custom_scope = hook&.call(subject)

        combine(default_scope, custom_scope)
      end

      def combine(*values)
        scopes = values.compact.map(&:to_s).reject(&:blank?)
        return if scopes.empty?

        scopes.map { |scope| "#{scope.bytesize}:#{scope}" }.join("\0")
      end
      private_class_method :combine

      def resolve_default(subject)
        context = context_for(subject)
        request = context.request if context&.respond_to?(:request)
        session_id = request&.session&.id&.to_s
        principal = if context&.respond_to?(:current_user, true)
          user = context.send(:current_user)
          "#{user.class.name}:#{user.respond_to?(:id) ? user.id : user.to_s}" if user
        end
        values = [session_id.presence, principal.presence].compact
        values.any? ? values.join("\0") : nil
      rescue StandardError
        nil
      end
      private_class_method :resolve_default

      def digest(value)
        value.nil? ? nil : Digest::SHA256.hexdigest(value.to_s)
      end

      def context_for(subject)
        return subject if subject.respond_to?(:request)
        return subject.connection if subject.respond_to?(:connection) && subject.connection.respond_to?(:request)

        subject.send(:view_context) if subject.respond_to?(:view_context, true)
      rescue StandardError
        nil
      end
      private_class_method :context_for
    end

    # Issues short-lived capabilities for a single reactive component stream.
    # A valid component identifier alone is not authorization to subscribe to
    # or update that component's Action Cable stream.
    module ReactiveStreamToken
      PURPOSE = "swift_ui_rails.reactive_stream"
      DEFAULT_EXPIRY = 10.minutes

      module_function

      def generate(component_id, expires_in: DEFAULT_EXPIRY, authorization_context: nil)
        raise ArgumentError, "component_id must be present" unless component_id.is_a?(String) && component_id.present?

        verifier.generate(
          {
            component_id: component_id,
            authorization_digest: ReactiveAuthorizationContext.digest(authorization_context)
          },
          expires_in: expires_in,
          purpose: PURPOSE
        )
      end

      def valid_for?(token, component_id, authorization_context: nil)
        return false unless token.is_a?(String) && token.present? && token.bytesize <= 4096
        return false unless component_id.is_a?(String) && component_id.present?

        payload = verifier.verified(token, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)

        authorized_component_id = payload["component_id"] || payload[:component_id]
        return false unless authorized_component_id.is_a?(String)
        authorized_context = payload["authorization_digest"] || payload[:authorization_digest]
        if authorized_context.present?
          return false unless secure_digest_match?(
            authorized_context,
            ReactiveAuthorizationContext.digest(authorization_context)
          )
        end

        secure_digest_match?(
          Digest::SHA256.digest(authorized_component_id),
          Digest::SHA256.digest(component_id)
        )
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageVerifier::InvalidMessage
        false
      end

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end
      private_class_method :verifier

      def secure_digest_match?(left, right)
        return false unless left.present? && right.present?

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
      private_class_method :secure_digest_match?
    end

    # Encrypted, expiring component snapshots preserve SwiftUI-like identity
    # and local data across stateless HTTP requests without exposing state in
    # the page or trusting browser-supplied props. The snapshot is bound to one
    # component class and DOM identifier and is renewed after every render.
    module ReactiveComponentSnapshot
      PURPOSE = "swift_ui_rails.reactive_component_snapshot"
      VERSION = 2
      DEFAULT_EXPIRY = 30.minutes
      MAX_TOKEN_BYTES = 128.kilobytes
      SnapshotTooLargeError = Class.new(SwiftUIRails::Error)
      UnsupportedValueError = Class.new(SwiftUIRails::Error)
      InvalidSnapshotError = Class.new(SwiftUIRails::SecurityError)
      ReplayedSnapshotError = Class.new(SwiftUIRails::SecurityError)
      @consume_mutex = Mutex.new
      @consumed_tokens = {}

      module_function

      def generate(component, component_id:, expires_in: DEFAULT_EXPIRY, authorization_context: nil)
        payload = {
          version: VERSION,
          component_id: component_id,
          component_class: component.class.name,
          props: component.send(:serialize_props),
          state: component.respond_to?(:state_values) ? component.state_values : {},
          bindings: component.respond_to?(:binding_values) ? component.binding_values : {},
          observed_stores: component.send(:observed_store_names),
          actions: component.respond_to?(:registered_action_descriptors) ? component.registered_action_descriptors : {},
          patch_baseline: component.send(:reactive_patch_baseline_token),
          authorization_digest: ReactiveAuthorizationContext.digest(authorization_context)
        }
        validate_snapshot_value!(payload)
        token = encryptor.encrypt_and_sign(
          payload,
          expires_in: expires_in,
          purpose: PURPOSE
        )
        if token.bytesize > MAX_TOKEN_BYTES
          raise SnapshotTooLargeError,
            "Reactive component snapshot exceeds #{MAX_TOKEN_BYTES} bytes"
        end

        token
      end

      def verified(token, component_id:, component_class:, authorization_context: nil)
        return unless token.is_a?(String) && token.present? && token.bytesize <= MAX_TOKEN_BYTES
        return unless component_id.is_a?(String) && component_class.is_a?(String)

        payload = encryptor.decrypt_and_verify(token, purpose: PURPOSE)
        return unless payload.is_a?(Hash) && payload["version"] == VERSION
        return unless secure_match?(payload["component_id"], component_id)
        return unless secure_match?(payload["component_class"], component_class)
        if payload["authorization_digest"].present?
          return unless secure_match?(
            payload["authorization_digest"],
            ReactiveAuthorizationContext.digest(authorization_context)
          )
        end

        payload
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      def consume!(token, component_id:, component_class:, authorization_context: nil)
        payload = verified(
          token,
          component_id: component_id,
          component_class: component_class,
          authorization_context: authorization_context
        )
        raise InvalidSnapshotError, "Invalid component snapshot" unless payload

        token_digest = Digest::SHA256.hexdigest(token)
        cache_key = "swift_ui_rails:consumed_snapshot:#{token_digest}"
        now = Time.now.to_f
        claimed_locally = @consume_mutex.synchronize do
          @consumed_tokens.delete_if { |_digest, expires_at| expires_at <= now }
          next false if @consumed_tokens.key?(token_digest)

          @consumed_tokens[token_digest] = now + DEFAULT_EXPIRY.to_f
          true
        end
        raise ReplayedSnapshotError, "Component snapshot was already used" unless claimed_locally

        claimed_globally = Rails.cache.write(
          cache_key,
          true,
          expires_in: DEFAULT_EXPIRY,
          unless_exist: true
        )
        unless claimed_globally
          @consume_mutex.synchronize { @consumed_tokens.delete(token_digest) }
          raise ReplayedSnapshotError, "Component snapshot was already used"
        end

        payload
      end

      # Active Record instances are tied to a process and database connection;
      # serializing them into a browser-carried snapshot produces a Hash on the
      # next request and violates declared prop types. Components carry scalar
      # identifiers and reload records through an observed resource instead.
      def validate_snapshot_value!(value, path = "snapshot", seen = {})
        if defined?(ActiveRecord::Base) && value.is_a?(ActiveRecord::Base)
          raise UnsupportedValueError,
            "#{path} cannot contain Active Record instances; pass a stable identifier instead"
        end

        case value
        when Array, Hash
          if seen.key?(value.object_id)
            raise UnsupportedValueError, "#{path} cannot contain cyclic collections"
          end

          seen[value.object_id] = true
          if value.is_a?(Array)
            value.each_with_index { |item, index| validate_snapshot_value!(item, "#{path}[#{index}]", seen) }
          else
            value.each do |key, item|
              validate_snapshot_value!(key, "#{path}.key", seen)
              validate_snapshot_value!(item, "#{path}.#{key}", seen)
            end
          end
          seen.delete(value.object_id)
        end

        value
      end

      def secure_match?(left, right)
        return false unless left.is_a?(String) && right.is_a?(String)

        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.digest(left),
          Digest::SHA256.digest(right)
        )
      end
      private_class_method :secure_match?

      def encryptor
        key = Rails.application.key_generator.generate_key(
          PURPOSE,
          ActiveSupport::MessageEncryptor.key_len
        )
        ActiveSupport::MessageEncryptor.new(key)
      end
      private_class_method :encryptor
    end

    # Builds the negotiated JSON response for both binding updates and
    # component-owned actions. The encrypted one-time snapshot carries the
    # opaque baseline key, so browsers never choose or tamper with the tree
    # used for a diff. Clients that do not advertise the protocol continue to
    # receive the complete HTML response.
    module RenderPatchResponses
      RENDER_PATCH_VERSION = 1

      private

      def reactive_render_payload(component:, snapshot:, rendered:, requested_version:)
        payload = {
          snapshot_token: component.send(:reactive_snapshot_token),
          stream_token: component.send(:reactive_stream_token)
        }
        return payload.merge(html: rendered) unless requested_version.to_i == RENDER_PATCH_VERSION

        patch = build_reactive_render_patch(component, snapshot, rendered)
        patch ? payload.merge(patch: patch) : payload.merge(html: rendered)
      rescue StandardError => e
        Rails.logger.warn("[SwiftUIRails] render patch fallback: #{e.class}")
        payload.merge(html: rendered)
      end

      def build_reactive_render_patch(component, snapshot, rendered)
        baseline_token = snapshot['patch_baseline'] || snapshot[:patch_baseline]
        return if baseline_token.blank?

        old_tree = fetch_reactive_patch_baseline(component, baseline_token)
        return log_render_patch_fallback(:baseline_cache_miss, token: baseline_token) unless old_tree

        new_tree = component.send(:reactive_patch_tree)
        return log_render_patch_fallback(:current_tree_unavailable) unless new_tree

        result = SwiftUIRails::RenderIR::PatchBuilder.call(
          old_tree: old_tree,
          new_tree: new_tree,
          full_html: rendered.to_s
        )
        return log_render_patch_fallback(result.reason) unless result.patch?

        result.to_h(component_id: component.component_id)
      end

      def fetch_reactive_patch_baseline(component, token)
        SwiftUIRails::RenderIR::PatchBaseline.fetch(
          token: token,
          component_id: component.component_id,
          component_class: component.class.name.to_s,
          authorization_context: ReactiveAuthorizationContext.resolve(self)
        )
      end

      def log_render_patch_fallback(reason, token: nil)
        Rails.logger.debug do
          fingerprint = " #{Digest::SHA256.hexdigest(token).first(12)}" if token
          "[SwiftUIRails] render patch fallback: #{reason}#{fingerprint}"
        end
        nil
      end
    end

    # Automatic re-rendering when state changes
    module Rendering
      extend ActiveSupport::Concern
      include RenderIRRendering

      included do
        class_attribute :reactive_rendering_enabled, default: true
      end

      class_methods do
        # Enable/disable reactive rendering
        def reactive_rendering(enabled = true)
          self.reactive_rendering_enabled = enabled
        end
      end
      
      private

      def reactive_snapshot_token
        @reactive_snapshot_token
      end

      def reactive_stream_token
        @reactive_stream_token
      end

      def reactive_patch_baseline_token
        @reactive_patch_baseline_token
      end

      def reactive_patch_tree
        @reactive_patch_tree
      end

      def serialize_props
        # Serialize current props for comparison
        props = {}

        prop_definitions = if self.class.respond_to?(:swift_props)
          self.class.swift_props
        elsif self.class.respond_to?(:prop_definitions)
          self.class.prop_definitions
        else
          {}
        end

        prop_definitions.each_key do |name|
          value = instance_variable_get("@#{name}")
          props[name] = serialize_value(value)
        end

        props
      end
      
      def serialize_value(value)
        case value
        when ActiveRecord::Base
          raise ReactiveComponentSnapshot::UnsupportedValueError,
            "Reactive props cannot contain Active Record instances; pass a stable identifier instead"
        when Array
          value.map { |v| serialize_value(v) }
        when Hash
          value.transform_values { |v| serialize_value(v) }
        else
          value
        end
      end
      
      def generate_state_fingerprint
        snapshot = if respond_to?(:reactive_state_snapshot)
          reactive_state_snapshot
        else
          { props: serialize_props, state: {}, bindings: {}, observed: {} }
        end

        Digest::SHA256.hexdigest(snapshot.to_json)
      end

      def observed_store_names
        return [] unless self.class.respond_to?(:observed_object_definitions)

        self.class.observed_object_definitions.map do |name, definition|
          (definition[:stream] || name).to_s
        end
      end

    end
    
    # Controller concern for handling component updates
    module ReactiveController
      extend ActiveSupport::Concern
      include RenderPatchResponses
      
      # Allowed components whitelist - CRITICAL SECURITY CONTROL
      ALLOWED_COMPONENTS = Set.new(%w[
        ButtonComponent
        CardComponent
        ModalComponent
        CounterComponent
        ReactiveCounterComponent
        ProductCardComponent
        ProductListComponent
        AuthFormComponent
        EnhancedLoginComponent
        EnhancedRegisterComponent
        AuthErrorComponent
        AuthLayoutComponent
        # Add new components here as they are created and security-reviewed
      ]).freeze

      class << self
        # Applications extend the deny-by-default registry through the public
        # initializer instead of patching this concern's constant. Reactive
        # entries must be explicit full class names; the historical short-name
        # list is reserved for the dynamic helper and is not an execution
        # allowlist.
        def allowed_component_names
          configured = Array(SwiftUIRails.configuration&.allowed_components).filter_map do |name|
            value = name.to_s
            next unless value.end_with?("Component")

            value
          end
          Set.new(ALLOWED_COMPONENTS.to_a + configured).freeze
        end
      end

      DANGEROUS_PROP_INVOCATION = %r!
        (?:
          (?:\A|[^A-Za-z0-9_])
          (?:__send__|send|public_send|eval|instance_eval|class_eval|module_eval|system|exec)
          \s*\(
          |
          \.\s*(?:constantize|safe_constantize)\b
          |
          (?:\A|[^A-Za-z0-9_])(?:constantize|safe_constantize)\s*\(
          |
          `[^`]*(?:`|\z)
          |
          %x\s*[\(\[\{<]
        )
      !ix.freeze
      MAX_UPDATE_REQUEST_BYTES = 256.kilobytes
      MAX_UPDATE_CHANGES = 100
      MAX_UPDATE_DEPTH = 6
      MAX_UPDATE_SCALAR_BYTES = 8.kilobytes
      UPDATE_RATE_LIMIT = 240
      
      included do
        # DO NOT skip CSRF verification - this is a critical security control
        # If CSRF must be disabled for specific use cases, implement alternative
        # authentication such as signed requests or API tokens
        before_action :verify_component_security, only: [:update_component]
      end
      
      def update_component
        return unless validate_reactive_update_envelope
        return unless check_reactive_update_rate_limit
        return unless verify_reactive_stream_authorization

        component_class_name = params[:component_class]
        snapshot = verified_component_snapshot(component_class_name)
        return unless snapshot

        # SECURITY: Validate component class against whitelist only after the
        # encrypted snapshot proves that this class was actually rendered.
        unless component_class_name.is_a?(String) && allowed_component_names.include?(component_class_name)
          # Log potential security breach attempt
          Rails.logger.error "[SECURITY] Attempted to instantiate unauthorized component: #{component_class_name}"
          audit_log_security_event(
            event_type: 'unauthorized_component_instantiation',
            component_class: component_class_name,
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          )

          render json: { error: 'Unauthorized component' }, status: :forbidden
          return
        end
        
        # Safe constantize with additional validation
        component_class = safe_constantize(component_class_name)
        
        # Props always come from the encrypted server snapshot. The browser may
        # submit only declared incremental binding/prop changes.
        component_props, binding_changes = component_update_attributes(
          component_class,
          snapshot.fetch("props", {}),
          params[:changes]
        )
        
        # Instantiate component with sanitized props
        component = component_class.restore_reactive_snapshot(
          props: component_props,
          state: snapshot.fetch("state", {}),
          bindings: snapshot.fetch("bindings", {}),
          component_id: params[:component_id]
        )
        binding_changes.each do |binding_name, value|
          component.public_send("#{binding_name}=", value)
        end

        # Render component with security context
        rendered = render_to_string(component)

        # Log successful component update for audit trail
        audit_log_component_update(
          component_class: component_class_name,
          component_id: params[:component_id]
        )

        # Return as Turbo Stream
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              params[:component_id],
              rendered
            )
          end

          format.json do
            render json: reactive_render_payload(
              component: component,
              snapshot: snapshot,
              rendered: rendered,
              requested_version: params[:render_patch_version]
            )
          end
        end
      rescue StandardError => e
        Rails.logger.error "[SECURITY] Component update failed: #{e.message}"
        render json: { error: 'Component update failed' }, status: :internal_server_error
      end
      
      # SECURITY: Safe request_update method for WebSocket updates
      def request_update(component_type, component_id, changes)
        raise SwiftUIRails::Error,
          "request_update is unsupported; use an authorized binding update or ObservableStore.invalidate"
      end
      
      private
      
      def component_registry
        @component_registry ||= build_component_registry
      end
      
      def build_component_registry
        registry = {}

        allowed_component_names.each do |class_name|
          begin
            klass = class_name.constantize
            registry[class_name.underscore] = klass
          rescue NameError
            Rails.logger.warn "Component class not found: #{class_name}"
          end
        end

        registry
      end
      
      def safe_constantize(class_name)
        # Double validation - belt and suspenders approach
        raise SecurityError, "Invalid component class" unless allowed_component_names.include?(class_name)
        
        # Ensure the constant exists and is a valid component
        klass = class_name.constantize
        
        # Verify it's actually a SwiftUI Rails component
        valid_application_component = defined?(ApplicationComponent) && klass < ApplicationComponent
        unless klass < SwiftUIRails::Component::Base || valid_application_component
          raise SecurityError, "Class is not a valid SwiftUI Rails component"
        end
        
        klass
      rescue NameError => e
        Rails.logger.error "[SECURITY] Failed to constantize component: #{class_name} - #{e.message}"
        raise SecurityError, "Component class not found"
      end
      
      def sanitize_component_props(props)
        props = normalize_parameter_hash(props)
        return {} unless props

        sanitize_prop_hash(props)
      end

      def allowed_component_names
        ReactiveController.allowed_component_names
      end

      def component_update_attributes(component_class, raw_props, raw_changes)
        prop_definitions = declared_definitions(component_class, :swift_props, :prop_definitions)
        binding_definitions = declared_definitions(component_class, :binding_definitions)
        snapshot_props = sanitize_component_props(raw_props)
        if component_class.respond_to?(:normalize_reactive_snapshot_props)
          snapshot_props = component_class.normalize_reactive_snapshot_props(snapshot_props)
        end

        component_props = filter_declared_values(
          snapshot_props,
          prop_definitions,
          value_kind: "prop"
        )
        binding_changes = {}

        changes = normalize_parameter_hash(raw_changes) || {}
        changes.each do |raw_change_name, raw_change|
          change_name = raw_change_name.to_s
          value_present, raw_value = extract_change_value(raw_change)
          next unless value_present

          keep, value = sanitize_prop_value(raw_value, ["changes", change_name])
          next unless keep

          namespace, declared_name = change_name.split(".", 2)
          next if declared_name.blank?

          case namespace
          when "binding"
            definition = binding_definitions[declared_name]
            binding_changes[declared_name] = value if valid_declared_value?(declared_name, value, definition, "binding")
          end
        end

        [component_props, binding_changes]
      end

      def normalize_parameter_hash(value)
        case value
        when ActionController::Parameters
          value.permitted? ? value.to_h : value.to_unsafe_h
        when Hash
          value
        end
      end

      def declared_definitions(component_class, *definition_methods)
        definitions = definition_methods.find do |method_name|
          component_class.respond_to?(method_name)
        end
        return {} unless definitions

        component_class.public_send(definitions).each_with_object({}) do |(name, definition), normalized|
          normalized[name.to_s] = definition
        end
      end

      def filter_declared_values(values, definitions, value_kind:)
        values.each_with_object({}) do |(raw_name, value), filtered|
          name = raw_name.to_s
          definition = definitions[name]
          filtered[name] = value if valid_declared_value?(name, value, definition, value_kind)
        end
      end

      def extract_change_value(raw_change)
        change = normalize_parameter_hash(raw_change)
        return [false, nil] unless change

        %w[new new_value].each do |key|
          return [true, change[key]] if change.key?(key)
          return [true, change[key.to_sym]] if change.key?(key.to_sym)
        end

        [false, nil]
      end

      def valid_declared_value?(name, value, definition, value_kind)
        unless definition
          Rails.logger.warn "[SECURITY] Ignored undeclared reactive #{value_kind}: #{name}"
          return false
        end

        allowed_type = definition[:type]
        type_matches = if allowed_type.is_a?(Array)
          allowed_type.any? { |type| value.is_a?(type) }
        else
          allowed_type.nil? || (value.nil? && value_kind == "prop") || value.is_a?(allowed_type)
        end
        return true if type_matches

        Rails.logger.warn "[SECURITY] Ignored invalid #{value_kind} type for #{name}"
        false
      end

      def sanitize_prop_hash(props, path = [])
        props.each_with_object({}) do |(key, value), sanitized|
          keep, sanitized_value = sanitize_prop_value(value, path + [key])
          sanitized[key] = sanitized_value if keep
        end
      end

      def sanitize_prop_value(value, path)
        case value
        when String
          if value.match?(DANGEROUS_PROP_INVOCATION)
            Rails.logger.warn "[SECURITY] Removed potentially dangerous prop: #{path.join('.')}"
            [false, nil]
          else
            [true, value.dup]
          end
        when Hash
          [true, sanitize_prop_hash(value, path)]
        when Array
          sanitized = []
          value.each_with_index do |item, index|
            keep, sanitized_value = sanitize_prop_value(item, path + [index])
            sanitized << sanitized_value if keep
          end
          [true, sanitized]
        else
          [true, value.respond_to?(:deep_dup) ? value.deep_dup : value]
        end
      end
      
      def verify_component_security
        # Additional security checks can be added here
        # For example: rate limiting, IP whitelisting, request signing
        
        # Verify request origin
        unless request.xhr? || request.format.turbo_stream?
          render json: { error: 'Invalid request format' }, status: :bad_request
          return false
        end
        
        true
      end

      def validate_reactive_update_envelope
        content_length = request.content_length.to_i
        if content_length > MAX_UPDATE_REQUEST_BYTES || request.raw_post.to_s.bytesize > MAX_UPDATE_REQUEST_BYTES
          render json: { error: "Reactive update is too large" }, status: :content_too_large
          return false
        end

        changes = normalize_parameter_hash(params[:changes]) || {}
        unless changes.size <= MAX_UPDATE_CHANGES && bounded_reactive_value?(changes)
          render json: { error: "Reactive update is too complex" }, status: :unprocessable_entity
          return false
        end

        true
      end

      def bounded_reactive_value?(value, depth = 0)
        return false if depth > MAX_UPDATE_DEPTH

        case value
        when ActionController::Parameters
          bounded_reactive_value?(value.to_unsafe_h, depth)
        when Hash
          value.size <= MAX_UPDATE_CHANGES && value.all? do |key, item|
            key.to_s.bytesize <= 256 && bounded_reactive_value?(item, depth + 1)
          end
        when Array
          value.size <= MAX_UPDATE_CHANGES && value.all? { |item| bounded_reactive_value?(item, depth + 1) }
        when String
          value.bytesize <= MAX_UPDATE_SCALAR_BYTES
        when Numeric, TrueClass, FalseClass, NilClass
          true
        else
          false
        end
      end

      def check_reactive_update_rate_limit
        count = Rails.cache.increment(
          "swift_ui_reactive_updates:#{request.remote_ip}",
          1,
          expires_in: 1.minute
        )
        return true if count.nil? || count <= UPDATE_RATE_LIMIT

        render json: { error: "Reactive update rate limit exceeded" }, status: :too_many_requests
        false
      end

      def verify_reactive_stream_authorization
        component_id = params[:component_id]&.to_s
        stream_token = params[:stream_token]&.to_s
        authorization_context = ReactiveAuthorizationContext.resolve(self)
        authorized = valid_reactive_component_id?(component_id) &&
          ReactiveStreamToken.valid_for?(
            stream_token,
            component_id,
            authorization_context: authorization_context
          )
        return true if authorized

        Rails.logger.error "[SECURITY] HTTP reactive update with invalid component capability"
        audit_log_security_event(
          event_type: "invalid_reactive_component_capability",
          component_id: component_id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render json: { error: "Unauthorized component update" }, status: :forbidden
        false
      end

      def verified_component_snapshot(component_class_name)
        token = params[:snapshot_token]&.to_s
        return ReactiveComponentSnapshot.consume!(
          token,
          component_id: params[:component_id]&.to_s,
          component_class: component_class_name,
          authorization_context: ReactiveAuthorizationContext.resolve(self)
        )
      rescue ReactiveComponentSnapshot::ReplayedSnapshotError
        Rails.logger.warn "[SECURITY] HTTP reactive update replayed a component snapshot"
        render json: { error: "Component changed; refresh and try again" }, status: :conflict
        nil
      rescue ReactiveComponentSnapshot::InvalidSnapshotError

        Rails.logger.error "[SECURITY] HTTP reactive update with invalid component snapshot"
        audit_log_security_event(
          event_type: "invalid_reactive_component_snapshot",
          component_id: params[:component_id],
          component_class: component_class_name,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render json: { error: "Unauthorized component snapshot" }, status: :forbidden
        nil
      end

      def valid_reactive_component_id?(component_id)
        component_id.is_a?(String) && component_id.length <= 200 &&
          component_id.match?(/\Aswift-ui-[\w-]+-\d+\z/)
      end
      
      def audit_log_security_event(event_type:, **details)
        # Implement security event logging
        # This should be sent to a security monitoring system
        Rails.logger.error "[SECURITY AUDIT] #{event_type}: #{details.to_json}"
        
        # In production, this would send to a SIEM system
        # SecurityEventLogger.log(event_type, details) if defined?(SecurityEventLogger)
      end
      
      def audit_log_component_update(component_class:, component_id:)
        # Log successful component updates for audit trail
        Rails.logger.info "[AUDIT] Component updated - Class: #{component_class}, ID: #{component_id}, IP: #{request.remote_ip}"
      end
    end
    
    # Background job for async updates (only define if Rails is loaded)
    if defined?(::ActiveJob::Base)
      class ReactiveUpdateJob < ::ActiveJob::Base
        queue_as :default
        
        def perform(component_class_name, component_id, props)
          # SECURITY: Validate inputs even in background job
          validate_component_class!(component_class_name)
          validate_component_id!(component_id)
          
          # Broadcast update via ActionCable
          ReactiveChannel.broadcast_to(
            component_id,
            {
              action: "update",
              component_class: component_class_name,
              props: sanitize_broadcast_props(props)
            }
          )
        rescue SecurityError => e
          Rails.logger.error "[SECURITY] ReactiveUpdateJob rejected: #{e.message}"
          raise
        end
        
        private
        
        def validate_component_class!(class_name)
          unless class_name.is_a?(String) && class_name.match?(/\A(?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*Component\z/)
            raise SecurityError, "Invalid component class name format"
          end

          unless ReactiveController.allowed_component_names.include?(class_name)
            raise SecurityError, "Component class not in whitelist: #{class_name}"
          end
        end
        
        def validate_component_id!(component_id)
          unless component_id.is_a?(String) && component_id.length <= 200 &&
              component_id.match?(/\Aswift-ui-[\w-]+-\d+\z/)
            raise SecurityError, "Invalid component ID format"
          end
        end
        
        def sanitize_broadcast_props(props)
          return {} unless props.is_a?(Hash)
          
          props.deep_stringify_keys.transform_values { |value| sanitize_broadcast_value(value) }
        end

        def sanitize_broadcast_value(value)
          case value
          when String
            sanitized = ActionController::Base.helpers.sanitize(value)
            SwiftUIRails::Security::URLValidator.contains_dangerous_pattern?(sanitized) ? "" : sanitized
          when Hash
            sanitize_broadcast_props(value)
          when Array
            value.map { |item| sanitize_broadcast_value(item) }
          else
            value
          end
        end
      end
    end
    
    # ActionCable channel for real-time updates (only define if ActionCable is loaded)
    if defined?(::ActionCable::Channel::Base)
      class ReactiveChannel < ::ActionCable::Channel::Base
        def subscribed
          component_id = params[:component_id]&.to_s
          stream_token = params[:stream_token]&.to_s
          component_class = params[:component_class]&.to_s
          snapshot_token = params[:snapshot_token]&.to_s
          unless valid_component_id?(component_id)
            Rails.logger.error "[SECURITY] WebSocket subscription with invalid component_id"
            reject
            return
          end

          authorization_context = ReactiveAuthorizationContext.resolve(self)
          unless ReactiveStreamToken.valid_for?(
            stream_token,
            component_id,
            authorization_context: authorization_context
          )
            Rails.logger.error "[SECURITY] WebSocket subscription with invalid stream token"
            reject
            return
          end

          snapshot = ReactiveComponentSnapshot.verified(
            snapshot_token,
            component_id: component_id,
            component_class: component_class,
            authorization_context: authorization_context
          )
          unless snapshot
            Rails.logger.error "[SECURITY] WebSocket subscription with invalid component snapshot"
            reject
            return
          end

          @authorized_component_id = component_id
          stream_for component_id
          Array(snapshot&.fetch("observed_stores", [])).each do |store_name|
            stream_from ObservableStore.stream_name(store_name)
          end
        end
        
        # Browser-originated WebSocket mutations cannot carry the one-time,
        # authorization-bound snapshot consumed by the HTTP update endpoint.
        # Keep the subscription read-only and never enqueue browser-supplied
        # component classes or props.
        def request_update(_data = nil, **_fields)
          Rails.logger.warn "[SECURITY] Unsupported WebSocket component mutation rejected"
          transmit({ action: "request_update_unsupported" })
        end
        
        private

        def valid_component_id?(component_id)
          component_id.is_a?(String) && component_id.length <= 200 &&
            component_id.match?(/\Aswift-ui-[\w-]+-\d+\z/)
        end
      end
    end
  end
end
