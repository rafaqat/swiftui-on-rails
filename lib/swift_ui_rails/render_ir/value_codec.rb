# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Encodes runtime values as JSON-native data without losing Hash insertion
    # order. Object keys in canonical RenderIR are sorted; ordered pairs retain
    # the attribute order expected by ActionView and existing HTML snapshots.
    module ValueCodec
      PAIRS_KEY = '$ordered_pairs'
      TYPE_KEY = '$ruby_type'

      module_function

      # The case is deliberately exhaustive: this is the sole Ruby-to-JSON
      # boundary and unsupported runtime types must have one deterministic exit.
      def encode(value, strict: true, path: '$') # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
        case value
        when Hash
          {
            PAIRS_KEY => value.map.with_index do |(key, child), index|
              [key.to_s, encode(child, strict: strict, path: "#{path}[#{index}]")]
            end
          }
        when Array
          value.map.with_index { |child, index| encode(child, strict: strict, path: "#{path}[#{index}]") }
        when Symbol
          value.to_s
        when String
          # ActiveSupport::SafeBuffer is a String subclass, but safe state is a
          # runtime capability and must not leak into the IR value model.
          String.new(value)
        when Integer, TrueClass, FalseClass, NilClass
          value
        when Float
          raise InvalidValue.new('RenderIR numbers must be finite.', path: path) unless value.finite?

          value
        else
          if strict
            raise InvalidValue.new(
              "RenderIR runtime value must be JSON-native, not #{value.class}.",
              path: path
            )
          end

          { TYPE_KEY => value.class.name.to_s }
        end
      end

      def decode(value)
        case value
        when Hash
          if value.keys == [PAIRS_KEY]
            value.fetch(PAIRS_KEY).to_h { |key, child| [key, decode(child)] }
          else
            value.to_h { |key, child| [key, decode(child)] }
          end
        when Array
          value.map { |child| decode(child) }
        else
          value
        end
      end

      def validate_encoded!(value, path: '$')
        EncodedValueValidator.validate!(value, path: path)
      end

      def encode_modifier_arguments(arguments)
        arguments.map.with_index do |argument, index|
          encode(argument, strict: false, path: "$.modifier.arguments[#{index}]")
        end
      end

      def encode_modifier_keywords(keywords)
        keywords.to_h do |key, value|
          [key.to_s, encode(value, strict: false, path: "$.modifier.keywords.#{key}")]
        end
      end
    end
  end
end

require_relative 'encoded_value_validator'
