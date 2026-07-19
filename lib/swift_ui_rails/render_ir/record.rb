# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Shared immutable value-object behavior for RenderIR records.
    class Record
      attr_reader :attributes

      def [](key)
        attributes[key.to_s]
      end

      def to_h
        attributes
      end

      def as_json(*)
        to_h
      end

      def canonical_json
        # Records have already passed bounded normalization. Disabling JSON's
        # smaller default nesting check keeps canonical serialization aligned
        # with RenderIR's explicit document/tree depth contract.
        JSON.generate(attributes, max_nesting: false)
      end

      def ==(other)
        other.instance_of?(self.class) && attributes == other.attributes
      end
      alias eql? ==

      def hash
        [self.class, attributes].hash
      end

      private

      def assign_attributes(attributes)
        @attributes = attributes
      end
    end

    # Internal structural checks used after JSON-native normalization.
    module Structure
      module_function

      def object!(value, path)
        return value if value.is_a?(Hash)

        raise InvalidStructure.new('RenderIR record must be an object.', path: path)
      end

      def array!(value, path)
        return value if value.is_a?(Array)

        raise InvalidStructure.new('RenderIR field must be an array.', path: path)
      end

      def plain_string!(value, path, field: 'field')
        return value if value.instance_of?(String) && !value.empty?

        raise InvalidStructure.new("RenderIR #{field} must be a non-empty string.", path: path)
      end

      def keys!(attributes, allowed:, required:, path:)
        missing = required - attributes.keys
        unless missing.empty?
          raise InvalidStructure.new(
            "RenderIR record is missing required key `#{missing.first}`.",
            path: path
          )
        end

        unknown = attributes.keys - allowed
        return if unknown.empty?

        raise InvalidStructure.new(
          "RenderIR record contains unknown key `#{unknown.first}`.",
          path: path
        )
      end
    end
  end
end
