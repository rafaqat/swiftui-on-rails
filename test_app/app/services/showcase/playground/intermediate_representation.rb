# frozen_string_literal: true

require "json"

module Showcase
  module Playground
    # Immutable, JSON-native representation of a compiled playground program.
    #
    # The source compiler intentionally emits small hashes. This wrapper gives
    # those hashes an explicit version boundary and typed traversal API without
    # coupling the compiler to the renderer. It also makes persisted programs
    # deterministic: equivalent hashes serialize in the same key order.
    module IntermediateRepresentation
      SCHEMA = "swift-ui-rails.playground-ir"
      VERSION = 1
      SUPPORTED_VERSIONS = [ VERSION ].freeze

      class InvalidValue < ArgumentError
        attr_reader :path

        def initialize(message, path: "$")
          @path = path.to_s.freeze
          super(message)
        end
      end

      module Normalizer
        module_function

        def call(value, path: "$", ancestors: {})
          case value
          when Hash
            with_container(value, path, ancestors) do |next_ancestors|
              pairs = value.map do |key, child|
                unless key.is_a?(String) || key.is_a?(Symbol)
                  raise InvalidValue.new("IR object keys must be strings.", path: path)
                end

                normalized_key = key.to_s
                [ normalized_key, call(child, path: child_path(path, normalized_key), ancestors: next_ancestors) ]
              end

              duplicate = pairs.group_by(&:first).find { |_key, entries| entries.length > 1 }
              if duplicate
                raise InvalidValue.new("IR object contains duplicate key `#{duplicate.first}`.", path: path)
              end

              pairs.sort_by(&:first).to_h.freeze
            end
          when Array
            with_container(value, path, ancestors) do |next_ancestors|
              value.each_with_index.map do |child, index|
                call(child, path: "#{path}[#{index}]", ancestors: next_ancestors)
              end.freeze
            end
          when String
            value.dup.freeze
          when Integer, TrueClass, FalseClass, NilClass
            value
          when Float
            raise InvalidValue.new("IR numbers must be finite.", path: path) unless value.finite?

            value
          else
            raise InvalidValue.new("IR values must be JSON-native, not #{value.class}.", path: path)
          end
        end

        def without_locations(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, child), output|
              output[key] = without_locations(child) unless key == "location"
            end.freeze
          when Array
            value.map { |child| without_locations(child) }.freeze
          else
            value
          end
        end

        def with_container(value, path, ancestors)
          if ancestors.key?(value.object_id)
            raise InvalidValue.new("IR values cannot contain cycles.", path: path)
          end

          yield ancestors.merge(value.object_id => true)
        end
        private_class_method :with_container

        def child_path(path, key)
          key.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) ? "#{path}.#{key}" : "#{path}[#{key.inspect}]"
        end
        private_class_method :child_path
      end

      class Record
        EMPTY_HASH = {}.freeze

        attr_reader :raw

        def initialize(raw, normalized: false)
          @raw = normalized ? raw : Normalizer.call(raw)
          @attributes = @raw.is_a?(Hash) ? @raw : EMPTY_HASH
        end

        def attributes
          @attributes
        end

        def [](key)
          attributes[key.to_s]
        end

        def key?(key)
          attributes.key?(key.to_s)
        end

        def to_h
          raw
        end

        def as_json(*)
          to_h
        end

        private

        def wrapped_array(key, wrapper)
          value = attributes[key]
          return [].freeze unless value.is_a?(Array)

          value.map { |child| wrapper.call(child) }.freeze
        end
      end

      class Location < Record
        def initialize(raw, normalized: false)
          super
          freeze
        end

        def line
          self["line"]
        end

        def column
          self["column"]
        end

        def end_line
          self["end_line"]
        end

        def end_column
          self["end_column"]
        end
      end

      class Expression < Record
        TYPES = %w[literal symbol variable index interpolation boolean not binary operation].freeze

        attr_reader :location

        def self.wrap(raw, normalized: false)
          new(raw, normalized: normalized)
        end

        def initialize(raw, normalized: false)
          super
          @location = Location.new(attributes["location"], normalized: true) if attributes["location"].is_a?(Hash)
          freeze
        end

        def type
          self["type"]
        end
      end

      class Modifier < Record
        attr_reader :arguments, :location

        def self.wrap(raw, normalized: false)
          new(raw, normalized: normalized)
        end

        def initialize(raw, normalized: false)
          super
          @arguments = wrapped_array("arguments", ->(value) { Expression.wrap(value, normalized: true) })
          @location = Location.new(attributes["location"], normalized: true) if attributes["location"].is_a?(Hash)
          freeze
        end

        def name
          self["name"]
        end
      end

      class Node < Record
        attr_reader :location

        def self.wrap(raw, normalized: false)
          normalized_raw = normalized ? raw : Normalizer.call(raw)
          type = normalized_raw.is_a?(Hash) ? normalized_raw["type"] : nil
          klass = {
            "view" => View,
            "for_each" => ForEach,
            "if" => Conditional,
            "unless" => Conditional
          }.fetch(type, Unknown)
          klass.new(normalized_raw, normalized: true)
        end

        def initialize(raw, normalized: false)
          super
          @location = Location.new(attributes["location"], normalized: true) if attributes["location"].is_a?(Hash)
        end

        def type
          self["type"]
        end
      end

      class View < Node
        attr_reader :arguments, :keywords, :modifiers, :children

        def initialize(raw, normalized: false)
          super
          @arguments = wrapped_array("arguments", ->(value) { Expression.wrap(value, normalized: true) })
          @keywords = if attributes["keywords"].is_a?(Hash)
            attributes["keywords"].transform_values { |value| Expression.wrap(value, normalized: true) }.freeze
          else
            {}.freeze
          end
          @modifiers = wrapped_array("modifiers", ->(value) { Modifier.wrap(value, normalized: true) })
          @children = wrapped_array("children", ->(value) { Node.wrap(value, normalized: true) })
          freeze
        end

        def name
          self["name"]
        end
      end

      class ForEach < Node
        attr_reader :collection, :identity, :children

        def initialize(raw, normalized: false)
          super
          @collection = Expression.wrap(attributes["collection"], normalized: true) if attributes.key?("collection")
          @identity = Expression.wrap(attributes["id"], normalized: true) if attributes.key?("id")
          @children = wrapped_array("children", ->(value) { Node.wrap(value, normalized: true) })
          freeze
        end

        def variable
          self["variable"]
        end
      end

      class Conditional < Node
        attr_reader :predicate, :then_children, :else_children

        def initialize(raw, normalized: false)
          super
          @predicate = Expression.wrap(attributes["predicate"], normalized: true) if attributes.key?("predicate")
          @then_children = wrapped_array("then", ->(value) { Node.wrap(value, normalized: true) })
          @else_children = wrapped_array("else", ->(value) { Node.wrap(value, normalized: true) })
          freeze
        end
      end

      class Unknown < Node
        def initialize(raw, normalized: false)
          super
          freeze
        end
      end

      class Document
        attr_reader :schema, :version, :language_version, :root, :attributes

        def self.wrap(value, version: VERSION, language_version: nil)
          return value if value.is_a?(self)

          normalized = Normalizer.call(value)
          if normalized.is_a?(Hash) && (normalized.key?("root") || normalized.key?("schema") || normalized.key?("version"))
            new(normalized)
          else
            envelope = {
              "schema" => SCHEMA,
              "version" => version,
              "root" => normalized
            }
            envelope["language_version"] = language_version if language_version
            new(envelope)
          end
        end

        def self.from_json(json)
          parsed = JSON.parse(json.to_s, create_additions: false, max_nesting: 100)
          wrap(parsed)
        rescue JSON::ParserError, JSON::NestingError => error
          raise InvalidValue.new("IR document is not valid JSON: #{error.message.to_s.lines.first.to_s.strip}")
        end

        def initialize(attributes)
          # Document is the public trust boundary. Always normalize here so a
          # caller cannot opt into the internal fast path with mutable input.
          @attributes = Normalizer.call(attributes)
          unless @attributes.is_a?(Hash)
            raise InvalidValue.new("IR document must be an object.")
          end

          @schema = @attributes["schema"]
          @version = @attributes["version"]
          @language_version = @attributes["language_version"]
          @root = Node.wrap(@attributes["root"], normalized: true)
          freeze
        end

        def program
          root.to_h
        end

        def to_h
          attributes
        end

        def as_json(*)
          to_h
        end

        def canonical_hash(include_locations: true)
          include_locations ? attributes : Normalizer.without_locations(attributes)
        end

        def canonical_json(include_locations: true)
          JSON.generate(canonical_hash(include_locations: include_locations))
        end

        def semantic_json
          canonical_json(include_locations: false)
        end
      end

      class << self
        def wrap(value, **options)
          Document.wrap(value, **options)
        end

        def canonical_json(value, **options)
          document_options = options.slice(:version, :language_version)
          serialization_options = options.slice(:include_locations)
          Document.wrap(value, **document_options).canonical_json(**serialization_options)
        end
      end
    end

    # Convenient short name after the Zeitwerk-safe long constant is loaded.
    IR = IntermediateRepresentation
  end
end
