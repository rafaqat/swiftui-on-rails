# frozen_string_literal: true

require 'digest'
require 'json'
require 'securerandom'

module SwiftUIRails
  module RenderIR
    # Short-lived, server-side storage for capability-free PatchTree baselines.
    # The opaque random token stays inside the encrypted reactive snapshot. The
    # cache entry is addressed by its digest and bound to component identity,
    # class, and the same authorization context as reactive capabilities.
    module PatchBaseline
      VERSION = 1
      PURPOSE = 'swift_ui_rails:patch_baseline:v1'
      DEFAULT_EXPIRY = 30.minutes
      MAX_BYTES = PatchTree::MAX_CACHE_BYTES
      TOKEN_PATTERN = /\A[A-Za-z0-9_-]{43}\z/
      COMPONENT_ID_PATTERN = /\A[A-Za-z][A-Za-z0-9_-]{0,199}\z/
      COMPONENT_CLASS_PATTERN = /\A(?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*Component\z/
      CAPABILITY_PATTERN = /\b[a-z][a-z0-9_]*:[0-9a-f]{24}:[1-9][0-9]*\b/

      module_function

      def issue
        SecureRandom.urlsafe_base64(32, false)
      end

      # Kept as one narrow seam so applications use Rails.cache while isolated
      # tests can supply a real cache implementation without replacing Rails'
      # dynamically delegated cache method.
      def cache
        Rails.cache
      end

      def store(token:, tree:, component_id:, component_class:, authorization_context:)
        validate_token!(token)
        validate_component_fields!(component_id, component_class)
        raise ArgumentError, 'tree must be a PatchTree' unless tree.is_a?(PatchTree)

        payload = {
          'authorization_digest' => authorization_digest(authorization_context),
          'component_class' => component_class,
          'component_id' => component_id,
          'tree' => tree.cache_payload,
          'version' => VERSION
        }
        serialized = JSON.generate(payload, max_nesting: PatchTree::MAX_CACHE_NESTING)
        return false if serialized.bytesize > MAX_BYTES || forbidden_payload?(serialized)

        cache.write(cache_key(token), payload, expires_in: DEFAULT_EXPIRY) == true
      rescue JSON::JSONError
        # JSONError covers both GeneratorError and NestingError (the latter is
        # not a GeneratorError), so an over-nested payload fails closed here
        # rather than escaping the best-effort baseline write.
        false
      end

      # Keep every binding and payload check explicit at the cache trust boundary.
      def fetch(token:, component_id:, component_class:, authorization_context:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        return unless valid_token?(token)
        return unless valid_component_fields?(component_id, component_class)

        payload = cache.read(cache_key(token))
        return unless payload.is_a?(Hash)

        serialized = JSON.generate(payload, max_nesting: PatchTree::MAX_CACHE_NESTING)
        return if serialized.bytesize > MAX_BYTES || forbidden_payload?(serialized)

        normalized = JSON.parse(serialized, max_nesting: PatchTree::MAX_CACHE_NESTING)
        return unless normalized.keys.sort == %w[authorization_digest component_class component_id tree version]
        return unless normalized.fetch('version') == VERSION
        return unless secure_match?(normalized.fetch('component_id'), component_id)
        return unless secure_match?(normalized.fetch('component_class'), component_class)
        return unless secure_optional_match?(
          normalized.fetch('authorization_digest'),
          authorization_digest(authorization_context)
        )

        PatchTree.from_cache_payload(normalized.fetch('tree'))
      rescue JSON::GeneratorError, JSON::ParserError, PatchTree::Unpatchable, KeyError, TypeError
        nil
      end

      def cache_key(token)
        "#{PURPOSE}:#{Digest::SHA256.hexdigest(token)}"
      end
      private_class_method :cache_key

      def validate_token!(token)
        return if valid_token?(token)

        raise ArgumentError, 'patch baseline token is invalid'
      end
      private_class_method :validate_token!

      def valid_token?(token)
        token.is_a?(String) && TOKEN_PATTERN.match?(token)
      end
      private_class_method :valid_token?

      def validate_component_fields!(component_id, component_class)
        return if valid_component_fields?(component_id, component_class)

        raise ArgumentError, 'patch baseline component identity is invalid'
      end
      private_class_method :validate_component_fields!

      def valid_component_fields?(component_id, component_class)
        component_id.is_a?(String) && COMPONENT_ID_PATTERN.match?(component_id) &&
          component_class.is_a?(String) && COMPONENT_CLASS_PATTERN.match?(component_class)
      end
      private_class_method :valid_component_fields?

      def authorization_digest(value)
        value.nil? ? nil : Digest::SHA256.hexdigest(value.to_s)
      end
      private_class_method :authorization_digest

      def secure_optional_match?(left, right)
        # Reactive capabilities only bind authorization when the initial
        # render had a context. An anonymous render can establish a Rails
        # session before its first action request, so a stored nil must retain
        # the same optional semantics as the signed snapshot and stream token.
        return true if left.nil?

        secure_match?(left, right)
      end
      private_class_method :secure_optional_match?

      def secure_match?(left, right)
        return false unless left.is_a?(String) && right.is_a?(String)

        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.digest(left),
          Digest::SHA256.digest(right)
        )
      end
      private_class_method :secure_match?

      def forbidden_payload?(serialized)
        serialized.match?(CAPABILITY_PATTERN) ||
          PatchTree::VOLATILE_ATTRIBUTES.any? { |attribute| serialized.include?(attribute) }
      end
      private_class_method :forbidden_payload?
    end
  end
end
