# frozen_string_literal: true

require 'json'
require 'nokogiri'

module SwiftUIRails
  module RenderIR
    # Capability-free DOM projection used by the keyed patch planner. The tree
    # is parsed from the validated renderer output so its attributes and browser
    # text contract are concrete, while request-local HTML is deliberately
    # omitted from the cache representation.
    class PatchTree # rubocop:disable Metrics/ClassLength
      VERSION = 1
      MAX_NODES = 4096
      MAX_DEPTH = 100
      MAX_SOURCE_BYTES = 2.megabytes
      MAX_CACHE_BYTES = 512.kilobytes
      MAX_CACHE_NESTING = (MAX_DEPTH * 3) + 16
      MAX_ATTRIBUTES_PER_NODE = 128
      MAX_ATTRIBUTE_BYTES = 16.kilobytes
      VOLATILE_ATTRIBUTES = %w[
        data-sui-snapshot
        data-sui-stream
        data-swift-ui-reactive-snapshot-token-value
        data-swift-ui-reactive-stream-token-value
        data-swift-ui-reactive-patch-token-value
        data-swift-ui-reactive-baseline-token-value
        data-swift-ui-reactive-render-revision-value
      ].freeze

      class Unpatchable < SwiftUIRails::RenderIR::Error; end

      # One keyed DOM element. `html` exists only on a tree built from the
      # current request and is never returned by #cache_payload.
      class Element
        attr_reader :key, :tag, :attributes, :text, :content, :children, :html

        # A DOM projection has several orthogonal fields by design; keeping
        # them explicit makes cache validation and protocol review auditable.
        def initialize( # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
          key:, tag:, attributes:, text:, content:, children:, html: nil
        )
          @key = key.freeze
          @tag = tag.freeze
          @attributes = attributes.to_h { |name, value| [name.freeze, value.freeze] }.freeze
          @text = text&.freeze
          @content = content.map { |kind, value| [kind.freeze, value.freeze].freeze }.freeze
          @children = children.dup.freeze
          @html = html&.freeze
          freeze
        end

        def cache_payload
          {
            'attributes' => attributes,
            'children' => children.map(&:cache_payload).freeze,
            'content' => content,
            'key' => key,
            'tag' => tag,
            'text' => text
          }.freeze
        end

        def equivalent?(other)
          other.is_a?(Element) && cache_payload == other.cache_payload
        end
      end

      attr_reader :root, :node_count

      def self.build(document:, html:)
        new(document: document, html: html).send(:build)
      end

      # Keep fail-closed cache-shape checks visible at the trust boundary.
      def self.from_cache_payload(payload) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        normalized = normalize_cache_payload(payload)
        unless normalized.keys.sort == %w[node_count root version] && normalized.fetch('version') == VERSION
          raise Unpatchable.new('Patch baseline has an unsupported shape or version.', path: '$.patch_baseline')
        end

        count = normalized.fetch('node_count')
        unless count.is_a?(Integer) && count.positive? && count <= MAX_NODES
          raise Unpatchable.new('Patch baseline node count is invalid.', path: '$.patch_baseline.node_count')
        end

        seen = {}
        root, actual_count = element_from_cache(normalized.fetch('root'), seen: seen, depth: 0)
        unless actual_count == count
          raise Unpatchable.new('Patch baseline node count does not match its tree.',
                                path: '$.patch_baseline.node_count')
        end

        allocate.tap { |tree| tree.send(:initialize_loaded, root, count) }
      rescue KeyError, TypeError => e
        raise Unpatchable.new("Patch baseline is malformed: #{e.message}", path: '$.patch_baseline')
      end

      def cache_payload
        {
          'node_count' => node_count,
          'root' => root.cache_payload,
          'version' => VERSION
        }.freeze
      end

      def each_element(&block)
        return enum_for(:each_element) unless block

        walk_element(root, &block)
      end

      private

      def initialize(document:, html:)
        @document = document
        @html = html.to_s
      end

      def initialize_loaded(root, count)
        @root = root
        @node_count = count
        freeze
      end

      def build
        validate_inputs!
        fragment = Nokogiri::HTML.fragment(@html)
        elements = fragment.css('*')
        validate_rendered_elements!(fragment, elements)

        @node_count = 0
        @seen_keys = {}
        @root = build_element(fragment.element_children.first, depth: 0)
        validate_expected_count!
        freeze
      end

      def validate_inputs!
        unless @document.is_a?(Document) && PatchLocator.reactive?(@document)
          raise Unpatchable.new('Only reactive RenderIR documents can produce patches.', path: '$.root')
        end

        if @document.each_node.any? { |node| node.kind == 'trusted_html' }
          raise Unpatchable.new(
            'RenderIR containing trusted_html cannot be persisted as a patch baseline.',
            path: '$.root'
          )
        end
        return unless @html.bytesize > MAX_SOURCE_BYTES

        raise Unpatchable.new('Rendered HTML exceeds the patch-tree byte limit.', path: '$.html')
      end

      # These independent checks deliberately reject every ambiguous DOM shape.
      def validate_rendered_elements!(fragment, elements) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        unless fragment.element_children.one?
          raise Unpatchable.new('Reactive patch HTML must have exactly one element root.', path: '$.html')
        end

        missing = elements.find { |element| element[PatchLocator::ATTRIBUTE].to_s.empty? }
        raise Unpatchable.new('Every rendered element must have a patch locator.', path: '$.html') if missing

        keys = elements.pluck(PatchLocator::ATTRIBUTE)
        invalid = keys.find { |key| !PatchLocator::KEY_PATTERN.match?(key) }
        raise Unpatchable.new('Rendered HTML has an invalid patch locator.', path: '$.html') if invalid

        reject_duplicates!(keys, 'patch locator')

        ids = elements.filter_map { |element| element['id'] }.reject(&:empty?)
        reject_duplicates!(ids, 'DOM id')

        expected = PatchLocator.for(@document).values
        return if keys.sort == expected.sort

        raise Unpatchable.new('Rendered HTML does not match the RenderIR locator set.', path: '$.html')
      end

      def reject_duplicates!(values, label)
        duplicate = values.group_by(&:itself).find { |_value, matches| matches.length > 1 }
        return unless duplicate

        raise Unpatchable.new("Rendered HTML contains a duplicate #{label}.", path: '$.html')
      end

      def build_element(element, depth:) # rubocop:disable Metrics/AbcSize
        raise Unpatchable.new('Patch tree exceeds its depth limit.', path: '$.html') if depth > MAX_DEPTH
        raise Unpatchable.new('Patch tree exceeds its node limit.', path: '$.html') if @node_count >= MAX_NODES

        @node_count += 1
        key = element[PatchLocator::ATTRIBUTE]
        raise Unpatchable.new('Patch tree contains a duplicate locator.', path: '$.html') if @seen_keys.key?(key)

        @seen_keys[key] = true

        child_elements = element.element_children.map { |child| build_element(child, depth: depth + 1) }
        content = direct_content(element)
        text = child_elements.empty? ? element.text.to_s : nil

        Element.new(
          key: key,
          tag: element.name.to_s.downcase,
          attributes: safe_attributes(element),
          text: text,
          content: content,
          children: child_elements,
          html: element.to_html
        )
      end

      def direct_content(element)
        element.children.map do |child|
          case child.type
          when Nokogiri::XML::Node::ELEMENT_NODE
            ['element', child[PatchLocator::ATTRIBUTE]].freeze
          when Nokogiri::XML::Node::TEXT_NODE, Nokogiri::XML::Node::CDATA_SECTION_NODE
            ['text', child.text.to_s].freeze
          else
            raise Unpatchable.new('Patch HTML cannot contain comments or processing nodes.', path: '$.html')
          end
        end.freeze
      end

      def safe_attributes(element) # rubocop:disable Metrics/AbcSize
        if element.attribute_nodes.length > MAX_ATTRIBUTES_PER_NODE
          raise Unpatchable.new('Patch element has too many attributes.', path: '$.html')
        end

        element.attribute_nodes.each_with_object({}) do |attribute, result|
          name = attribute.name.to_s.downcase
          next if name == PatchLocator::ATTRIBUTE || volatile_attribute?(name)

          reject_token_attribute!(name)

          value = attribute.value.to_s
          if name.bytesize > 128 || value.bytesize > MAX_ATTRIBUTE_BYTES
            raise Unpatchable.new('Patch element attribute exceeds its byte limit.', path: '$.html')
          end

          result[name] = value.freeze
        end.freeze
      end

      def reject_token_attribute!(name)
        return unless name.include?('token')

        raise Unpatchable.new(
          'Patch HTML contains a token-bearing attribute that cannot enter a baseline.',
          path: '$.html'
        )
      end

      def volatile_attribute?(name)
        VOLATILE_ATTRIBUTES.include?(name) ||
          (name.start_with?('data-swift-ui-reactive-') && name.include?('token'))
      end

      def validate_expected_count!
        expected_count = PatchLocator.for(@document).length
        return if node_count == expected_count

        raise Unpatchable.new('Patch tree node count does not match RenderIR.', path: '$.html')
      end

      def walk_element(element, &block)
        yield element
        element.children.each { |child| walk_element(child, &block) }
      end

      class << self
        private

        def normalize_cache_payload(payload)
          serialized = JSON.generate(payload, max_nesting: MAX_CACHE_NESTING)
          if serialized.bytesize > MAX_CACHE_BYTES
            raise Unpatchable.new(
              'Patch baseline exceeds its aggregate byte limit.',
              path: '$.patch_baseline'
            )
          end

          JSON.parse(serialized, max_nesting: MAX_CACHE_NESTING)
        rescue JSON::GeneratorError, JSON::ParserError => e
          raise Unpatchable.new("Patch baseline is not JSON-safe: #{e.message}", path: '$.patch_baseline')
        end

        # Cache decoding remains explicit so every accepted field is auditable.
        def element_from_cache(payload, seen:, depth:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          if depth > MAX_DEPTH || !payload.is_a?(Hash)
            raise Unpatchable.new('Patch baseline tree is too deep or malformed.', path: '$.patch_baseline.root')
          end

          expected_keys = %w[attributes children content key tag text]
          unless payload.keys.sort == expected_keys
            raise Unpatchable.new('Patch baseline element has an invalid shape.', path: '$.patch_baseline.root')
          end

          key = payload.fetch('key')
          tag = payload.fetch('tag')
          attributes = payload.fetch('attributes')
          content = payload.fetch('content')
          children_payload = payload.fetch('children')
          text = payload.fetch('text')
          validate_cached_fields!(key, tag, attributes, content, children_payload, text, seen)

          count = 1
          children = children_payload.map do |child|
            parsed, child_count = element_from_cache(child, seen: seen, depth: depth + 1)
            count += child_count
            parsed
          end
          raise Unpatchable.new('Patch baseline exceeds its node limit.', path: '$.patch_baseline') if count > MAX_NODES

          element = Element.new(
            key: key,
            tag: tag,
            attributes: attributes.transform_values(&:freeze),
            text: text,
            content: content.map(&:freeze).freeze,
            children: children
          )
          validate_content_children!(element)
          [element, count]
        end

        def validate_cached_fields!( # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
          key, tag, attributes, content, children, text, seen
        )
          unless key.is_a?(String) && PatchLocator::KEY_PATTERN.match?(key) && !seen.key?(key)
            raise Unpatchable.new('Patch baseline locator is invalid or duplicated.', path: '$.patch_baseline.root.key')
          end

          seen[key] = true
          unless tag.is_a?(String) && tag.match?(/\A[a-z][a-z0-9:-]*\z/)
            raise Unpatchable.new('Patch baseline tag is invalid.', path: '$.patch_baseline.root.tag')
          end
          unless attributes.is_a?(Hash) && attributes.length <= MAX_ATTRIBUTES_PER_NODE &&
                 attributes.all? { |name, value| cached_attribute?(name, value) }
            raise Unpatchable.new('Patch baseline attributes are invalid.', path: '$.patch_baseline.root.attributes')
          end
          unless content.is_a?(Array) && content.all? { |entry| cached_content?(entry) } && children.is_a?(Array)
            raise Unpatchable.new('Patch baseline children are invalid.', path: '$.patch_baseline.root.children')
          end
          return if text.nil? || (text.is_a?(String) && text.bytesize <= MAX_CACHE_BYTES)

          raise Unpatchable.new('Patch baseline text is invalid.', path: '$.patch_baseline.root.text')
        end

        def cached_attribute?(name, value)
          name.is_a?(String) && value.is_a?(String) && name.bytesize <= 128 &&
            value.bytesize <= MAX_ATTRIBUTE_BYTES && name != PatchLocator::ATTRIBUTE &&
            VOLATILE_ATTRIBUTES.exclude?(name) && name.exclude?('token')
        end

        def cached_content?(entry)
          return false unless entry.is_a?(Array) && entry.length == 2 && entry.last.is_a?(String)

          case entry.first
          when 'element'
            PatchLocator::KEY_PATTERN.match?(entry.last)
          when 'text'
            entry.last.bytesize <= MAX_CACHE_BYTES
          else
            false
          end
        end

        def validate_content_children!(element)
          referenced_keys = element.content.filter_map { |kind, value| value if kind == 'element' }
          return if referenced_keys == element.children.map(&:key)

          raise Unpatchable.new(
            'Patch baseline content does not match its element children.',
            path: '$.patch_baseline.root.content'
          )
        end
      end
    end
  end
end
