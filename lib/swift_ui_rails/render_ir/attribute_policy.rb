# frozen_string_literal: true

require_relative 'iframe_policy'
require_relative 'semantic_attribute_policy'
require_relative '../security/url_validator'

module SwiftUIRails
  module RenderIR
    # Security and shape policy for the HTML-facing portion of a resolved node.
    # Imported IR receives the same URL and embed checks as Ruby-authored DSL.
    class AttributePolicy
      TAG_PATTERN = /\A[a-z][a-z0-9:-]*\z/i
      ATTRIBUTE_PATTERN = /\A[a-zA-Z_:][a-zA-Z0-9_.:-]*\z/
      EXPECTED_PROPS = %w[attribute_pairs paired tag].freeze
      FORBIDDEN_TAGS = %w[base embed link meta object script style].freeze
      PORTABLE_FORBIDDEN_TAGS = %w[iframe].freeze
      FORBIDDEN_ATTRIBUTES = %w[srcdoc srcset].freeze
      URL_ATTRIBUTES = %w[action cite formaction href poster src xlink:href].freeze
      def initialize(profile:)
        @profile = profile
        @semantic_attribute_policy = SemanticAttributePolicy.new
      end

      def validate!(node, path)
        validate_props!(node, path)
        tag = node.props.fetch('tag').downcase
        pairs = node.props.fetch('attribute_pairs')
        names = pairs.map.with_index do |pair, index|
          validate_pair!(pair, tag, "#{path}.props.attribute_pairs[#{index}]")
          pair.first.downcase
        end

        reject_duplicate_names!(names, path)
        IframePolicy.validate!(pairs, path) if tag == 'iframe'
      end

      private

      def validate_props!(node, path)
        validate_prop_keys!(node, path)
        validate_tag!(node.props.fetch('tag'), path)
        validate_attribute_pairs!(node, path)
        return if [true, false].include?(node.props.fetch('paired'))

        raise InvalidStructure.new('RenderIR element paired must be boolean.', path: "#{path}.props.paired")
      end

      def validate_prop_keys!(node, path)
        return if node.props.keys == EXPECTED_PROPS

        raise InvalidStructure.new('RenderIR element props have an invalid shape.', path: "#{path}.props")
      end

      def validate_attribute_pairs!(node, path)
        return if node.props.fetch('attribute_pairs').is_a?(Array)

        raise InvalidStructure.new(
          'RenderIR element attribute_pairs must be an array.',
          path: "#{path}.props.attribute_pairs"
        )
      end

      def validate_tag!(tag, path)
        normalized = tag.downcase if tag.instance_of?(String)
        safe = normalized && TAG_PATTERN.match?(tag) && FORBIDDEN_TAGS.exclude?(normalized)
        safe &&= !(@profile == 'portable' && PORTABLE_FORBIDDEN_TAGS.include?(normalized))
        return if safe

        raise InvalidStructure.new('RenderIR element tag is invalid or forbidden.', path: "#{path}.props.tag")
      end

      def validate_pair!(pair, tag, path)
        validate_pair_shape!(pair, path)
        name = pair.first.downcase
        validate_attribute_name!(pair.first, name, path)
        if FORBIDDEN_ATTRIBUTES.include?(name)
          raise InvalidStructure.new('RenderIR attribute is not supported by the security policy.', path: "#{path}[0]")
        end

        ValueCodec.validate_encoded!(pair.last, path: "#{path}[1]")
        @semantic_attribute_policy.validate!(pair.first, ValueCodec.decode(pair.last), path)
        validate_url!(tag, name, pair.last, path) if URL_ATTRIBUTES.include?(name)
      end

      def validate_pair_shape!(pair, path)
        return if pair.is_a?(Array) && pair.length == 2 && pair.first.instance_of?(String)

        raise InvalidStructure.new('RenderIR attribute must be a name/value pair.', path: path)
      end

      def validate_attribute_name!(original_name, normalized_name, path)
        return if ATTRIBUTE_PATTERN.match?(original_name) && !normalized_name.match?(/\Aon[a-z]/)

        raise InvalidStructure.new('RenderIR attribute name is invalid or unsafe.', path: "#{path}[0]")
      end

      def reject_duplicate_names!(names, path)
        duplicate = names.group_by(&:itself).find { |_name, entries| entries.length > 1 }
        return unless duplicate

        raise InvalidStructure.new(
          "RenderIR element contains duplicate attribute `#{duplicate.first}`.",
          path: "#{path}.props.attribute_pairs"
        )
      end

      def validate_url!(tag, name, encoded_value, path)
        value = ValueCodec.decode(encoded_value)
        unless value.instance_of?(String)
          raise InvalidStructure.new('RenderIR URL attributes must be strings.', path: "#{path}[1]")
        end
        return if safe_url(tag, name, value) == value

        raise InvalidStructure.new('RenderIR URL attribute is invalid or unsafe.', path: "#{path}[1]")
      end

      def safe_url(tag, name, value)
        return safe_source(tag, value) if name == 'src'
        return Security::URLValidator.validate_image_src(value, fallback: nil) if name == 'poster'

        Security::URLValidator.validate_link_href(value, fallback: nil)
      end

      def safe_source(tag, value)
        return value if tag == 'iframe' && value == 'about:blank'
        return Security::URLValidator.validate_embed_src(value) if tag == 'iframe'
        return Security::URLValidator.validate_image_src(value, fallback: nil) if tag == 'img'

        Security::URLValidator.validate_url(value, allow_relative: true, fallback: nil)
      end
    end
  end
end
