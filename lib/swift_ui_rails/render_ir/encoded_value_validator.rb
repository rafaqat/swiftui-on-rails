# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Validates the unambiguous JSON codec used for HTML attribute values.
    module EncodedValueValidator
      module_function

      def validate!(value, path: '$')
        case value
        when Hash
          validate_hash!(value, path)
        when Array
          value.each_with_index { |child, index| validate!(child, path: "#{path}[#{index}]") }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        else
          raise InvalidStructure.new('RenderIR encoded attribute value is invalid.', path: path)
        end
      end

      def validate_hash!(value, path)
        return validate_ordered_pairs!(value, path) if value.key?(ValueCodec::PAIRS_KEY)
        return validate_typed_placeholder!(value, path) if value.key?(ValueCodec::TYPE_KEY)

        value.each { |key, child| validate!(child, path: "#{path}.#{key}") }
        value
      end
      private_class_method :validate_hash!

      def validate_ordered_pairs!(value, path)
        pairs = ordered_pairs!(value, path)
        names = pairs.map.with_index do |pair, index|
          validate_ordered_pair!(pair, "#{path}.#{ValueCodec::PAIRS_KEY}[#{index}]")
        end
        reject_duplicate_names!(names, path)
        value
      end
      private_class_method :validate_ordered_pairs!

      def ordered_pairs!(value, path)
        pairs = value.fetch(ValueCodec::PAIRS_KEY)
        return pairs if value.keys == [ValueCodec::PAIRS_KEY] && pairs.is_a?(Array)

        raise InvalidStructure.new('RenderIR ordered-pair value has an invalid shape.', path: path)
      end
      private_class_method :ordered_pairs!

      def validate_ordered_pair!(pair, path)
        unless pair.is_a?(Array) && pair.length == 2 && pair.first.instance_of?(String)
          raise InvalidStructure.new('RenderIR ordered-pair entry must be a string/value pair.', path: path)
        end

        validate!(pair.last, path: "#{path}[1]")
        pair.first
      end
      private_class_method :validate_ordered_pair!

      def reject_duplicate_names!(names, path)
        duplicate = names.group_by(&:itself).find { |_name, entries| entries.length > 1 }
        return unless duplicate

        raise InvalidStructure.new(
          "RenderIR ordered-pair value contains duplicate key `#{duplicate.first}`.",
          path: path
        )
      end
      private_class_method :reject_duplicate_names!

      def validate_typed_placeholder!(value, path)
        valid = value.keys == [ValueCodec::TYPE_KEY] && value.fetch(ValueCodec::TYPE_KEY).instance_of?(String)
        return value if valid

        raise InvalidStructure.new('RenderIR typed placeholder has an invalid shape.', path: path)
      end
      private_class_method :validate_typed_placeholder!
    end
  end
end
