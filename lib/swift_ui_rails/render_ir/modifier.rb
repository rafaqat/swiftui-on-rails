# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # A resolved modifier invocation. Array order is semantically significant.
    class Modifier < Record
      ALLOWED_KEYS = %w[arguments keywords name].freeze
      REQUIRED_KEYS = %w[name].freeze
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      attr_reader :name, :arguments, :keywords

      def self.from_h(value = nil, path: '$', **attributes)
        value = keyword_hash(value, attributes)
        normalized = Normalizer.call(value, path: path)
        from_normalized(normalized, path: path)
      end

      # Internal fast path for data already normalized by an enclosing record.
      def self.from_normalized(value, path: '$')
        object = allocate
        object.send(:initialize_from_normalized, value, path)
        object
      end
      private_class_method :from_normalized

      def self.keyword_hash(value, attributes)
        return attributes if value.nil?
        return value if attributes.empty?

        raise ArgumentError, 'pass a RenderIR modifier as a hash or keyword fields, not both'
      end
      private_class_method :keyword_hash

      def initialize(name:, arguments: EMPTY_ARRAY, keywords: EMPTY_HASH)
        super()
        @name = Structure.plain_string!(Normalizer.call(name, path: '$.name'), '$.name', field: 'modifier name')
        @arguments = Structure.array!(Normalizer.call(arguments, path: '$.arguments'), '$.arguments')
        @keywords = Structure.object!(Normalizer.call(keywords, path: '$.keywords'), '$.keywords')
        assign_attributes(canonical_attributes)
        freeze
      end

      private

      def initialize_from_normalized(attributes, path)
        Structure.object!(attributes, path)
        Structure.keys!(attributes, allowed: ALLOWED_KEYS, required: REQUIRED_KEYS, path: path)

        @name = Structure.plain_string!(attributes.fetch('name'), "#{path}.name", field: 'modifier name')
        @arguments = Structure.array!(attributes.fetch('arguments', EMPTY_ARRAY), "#{path}.arguments")
        @keywords = Structure.object!(attributes.fetch('keywords', EMPTY_HASH), "#{path}.keywords")
        assign_attributes(canonical_attributes)
        freeze
      end

      def canonical_attributes
        {
          'arguments' => arguments,
          'keywords' => keywords,
          'name' => name
        }.freeze
      end
    end
  end
end
