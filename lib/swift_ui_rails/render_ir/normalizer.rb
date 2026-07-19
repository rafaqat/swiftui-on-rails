# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Converts values into a deterministic, deeply frozen JSON data tree.
    module Normalizer # rubocop:disable Metrics/ModuleLength
      MAX_DEPTH = 100
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      module_function

      def call(
        value,
        path: '$',
        ancestors: nil,
        depth: 0,
        max_depth: MAX_DEPTH
      )
        raise InvalidValue.new("RenderIR values cannot exceed #{max_depth} levels.", path: path) if depth > max_depth

        case value
        when Hash
          normalize_hash(
            value, path: path, ancestors: container_ancestors(ancestors), depth: depth, max_depth: max_depth
          )
        when Array
          normalize_array(
            value, path: path, ancestors: container_ancestors(ancestors), depth: depth, max_depth: max_depth
          )
        when String
          normalize_string(value, path: path)
        when Integer, TrueClass, FalseClass, NilClass
          value
        when Float
          normalize_float(value, path)
        else
          raise_invalid_type!(value, path)
        end
      end

      def normalize_hash(value, path:, ancestors:, depth:, max_depth:)
        return EMPTY_HASH if value.empty?

        with_container(value, path, ancestors) do |next_ancestors|
          normalized = {}
          value.each do |key, child|
            normalized_key = normalize_key(key, path)
            reject_duplicate_key!(normalized, normalized_key, path)
            normalized[normalized_key] = call(
              child,
              path: child_path(path, normalized_key),
              ancestors: next_ancestors,
              depth: depth + 1,
              max_depth: max_depth
            )
          end

          sort_hash(normalized)
        end
      end
      private_class_method :normalize_hash

      def normalize_array(value, path:, ancestors:, depth:, max_depth:)
        return EMPTY_ARRAY if value.empty?

        with_container(value, path, ancestors) do |next_ancestors|
          value.each_with_index.map do |child, index|
            call(
              child,
              path: "#{path}[#{index}]",
              ancestors: next_ancestors,
              depth: depth + 1,
              max_depth: max_depth
            )
          end.freeze
        end
      end
      private_class_method :normalize_array

      def normalize_key(key, path)
        unless key.instance_of?(String) || key.instance_of?(Symbol)
          raise InvalidValue.new('RenderIR object keys must be strings.', path: path)
        end

        normalize_string(key.to_s, path: path)
      end
      private_class_method :normalize_key

      def normalize_string(value, path:)
        unless value.instance_of?(String)
          raise InvalidValue.new(
            "RenderIR strings must be plain String values, not #{value.class}.",
            path: path
          )
        end

        # encode! is a no-op for already-UTF-8-tagged strings and never raises
        # on malformed bytes, so an explicit validity check is required to keep
        # invalid UTF-8 out of the frozen IR.
        normalized = value.dup.encode!(Encoding::UTF_8)
        unless normalized.valid_encoding?
          raise InvalidValue.new('RenderIR strings must be valid UTF-8.', path: path)
        end

        normalized.freeze
      rescue EncodingError => e
        raise InvalidValue.new("RenderIR strings must be valid UTF-8: #{e.message}", path: path)
      end
      private_class_method :normalize_string

      def normalize_float(value, path)
        raise InvalidValue.new('RenderIR numbers must be finite.', path: path) unless value.finite?

        value
      end
      private_class_method :normalize_float

      def raise_invalid_type!(value, path)
        raise InvalidValue.new("RenderIR values must be JSON-native data, not #{value.class}.", path: path)
      end
      private_class_method :raise_invalid_type!

      def reject_duplicate_key!(values, key, path)
        return unless values.key?(key)

        raise InvalidValue.new("RenderIR object contains duplicate key `#{key}`.", path: path)
      end
      private_class_method :reject_duplicate_key!

      def sort_hash(value)
        return value.freeze if value.length == 1

        value.sort.to_h.freeze
      end
      private_class_method :sort_hash

      def container_ancestors(ancestors)
        ancestors || {}.compare_by_identity
      end
      private_class_method :container_ancestors

      def with_container(value, path, ancestors)
        added = false
        raise InvalidValue.new('RenderIR values cannot contain cycles.', path: path) if ancestors.key?(value)

        ancestors[value] = true
        added = true
        yield ancestors
      ensure
        ancestors.delete(value) if added
      end
      private_class_method :with_container

      def child_path(path, key)
        return "#{path}.#{key}" if key.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

        "#{path}[#{key.inspect}]"
      end
      private_class_method :child_path
    end # rubocop:enable Metrics/ModuleLength
  end
end
