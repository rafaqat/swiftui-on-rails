# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Versioned envelope around one resolved semantic view tree.
    class Document < Record # rubocop:disable Metrics/ClassLength
      ALLOWED_KEYS = %w[language_version metadata profile root schema version].freeze
      REQUIRED_KEYS = %w[profile root schema version].freeze
      EMPTY_HASH = {}.freeze
      MAX_SERIALIZED_DEPTH = (Normalizer::MAX_DEPTH * 3) + 16

      attr_reader :schema, :version, :profile, :language_version, :metadata, :root

      def self.from_h(value = nil, path: '$', **attributes)
        value = keyword_hash(value, attributes)
        normalized = Normalizer.call(value, path: path, max_depth: MAX_SERIALIZED_DEPTH)
        object = allocate
        object.send(:initialize_from_normalized, normalized, path)
        object
      end

      def self.keyword_hash(value, attributes)
        return attributes if value.nil?
        return value if attributes.empty?

        raise ArgumentError, 'pass a RenderIR document as a hash or keyword fields, not both'
      end
      private_class_method :keyword_hash

      def self.from_json(json)
        parsed = JSON.parse(json.to_s, create_additions: false, max_nesting: MAX_SERIALIZED_DEPTH)
        from_h(parsed)
      rescue JSON::ParserError => e
        message = e.message.to_s.lines.first.to_s.strip
        raise InvalidValue, "RenderIR document is not valid JSON: #{message}"
      end

      def initialize(
        root:,
        profile: DEFAULT_PROFILE,
        metadata: EMPTY_HASH,
        language_version: nil,
        version: VERSION
      )
        super()
        @schema = SCHEMA
        @version = validate_version(Normalizer.call(version, path: '$.version'), '$')
        @profile = Structure.plain_string!(
          Normalizer.call(profile, path: '$.profile'),
          '$.profile',
          field: 'profile'
        )
        @language_version = Normalizer.call(language_version, path: '$.language_version')
        @metadata = Structure.object!(Normalizer.call(metadata, path: '$.metadata'), '$.metadata')
        @root = root.is_a?(Node) ? root : Node.from_h(root, path: '$.root')
        validate_node_depth!(@root)
        assign_attributes(canonical_attributes)
        freeze
      end

      def each_node(&block)
        return enum_for(:each_node) unless block

        root.each_node(&block)
      end

      private

      def initialize_from_normalized(attributes, path)
        Structure.object!(attributes, path)
        Structure.keys!(attributes, allowed: ALLOWED_KEYS, required: REQUIRED_KEYS, path: path)

        assign_header(attributes, path)
        assign_payload(attributes, path)
        assign_attributes(canonical_attributes)
        freeze
      end

      def assign_header(attributes, path)
        @schema = validate_schema(attributes.fetch('schema'), path)
        @version = validate_version(attributes.fetch('version'), path)
        @profile = Structure.plain_string!(attributes.fetch('profile'), "#{path}.profile", field: 'profile')
        @language_version = attributes.fetch('language_version', nil)
      end

      def assign_payload(attributes, path)
        @metadata = Structure.object!(attributes.fetch('metadata', EMPTY_HASH), "#{path}.metadata")
        @root = Node.send(:from_normalized, attributes.fetch('root'), path: "#{path}.root")
        validate_node_depth!(@root)
      end

      def validate_schema(value, path)
        return value if value == SCHEMA

        raise InvalidStructure.new(
          "RenderIR schema must be `#{SCHEMA}`.",
          path: "#{path}.schema"
        )
      end

      def validate_version(value, path)
        return value if SUPPORTED_VERSIONS.include?(value)

        raise UnsupportedVersion.new(
          "RenderIR version #{value.inspect} is not supported; expected one of #{SUPPORTED_VERSIONS.join(', ')}.",
          path: "#{path}.version"
        )
      end

      def canonical_attributes
        {
          'language_version' => language_version,
          'metadata' => metadata,
          'profile' => profile,
          'root' => root.to_h,
          'schema' => schema,
          'version' => version
        }.freeze
      end

      def validate_node_depth!(node, depth = 0)
        if depth > Normalizer::MAX_DEPTH
          raise InvalidValue.new(
            "RenderIR values cannot exceed #{Normalizer::MAX_DEPTH} levels.",
            path: '$.root'
          )
        end

        node.children.each { |child| validate_node_depth!(child, depth + 1) }
      end
    end
  end
end
