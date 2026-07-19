# frozen_string_literal: true

require 'json'

module SwiftUIRails
  # Immutable, resolved view-tree representation shared by compilers, linters,
  # renderers, and development tools.
  #
  # RenderIR deliberately contains data, never executable Ruby or rendered HTML.
  # Every value crossing this boundary is normalized to the JSON data model and
  # defensively frozen.
  module RenderIR
    SCHEMA = 'swift-ui-rails.render-ir'
    VERSION = 1
    SUPPORTED_VERSIONS = [VERSION].freeze
    DEFAULT_PROFILE = 'trusted'

    # Base error carrying the exact JSON-style path that failed validation.
    class Error < SwiftUIRails::Error
      attr_reader :path

      def initialize(message, path: '$')
        @path = path.to_s.dup.freeze
        super(message)
      end
    end

    # Raised when a value cannot be represented safely in RenderIR.
    class InvalidValue < Error; end

    # Raised when an IR record has an invalid or ambiguous shape.
    class InvalidStructure < Error; end

    # Raised when a document targets a schema version this runtime cannot read.
    class UnsupportedVersion < Error; end

    class << self
      def node(**attributes)
        Node.new(**attributes)
      end

      def modifier(**attributes)
        Modifier.new(**attributes)
      end

      def document(root:, **attributes)
        Document.new(root: root, **attributes)
      end

      # Kept explicit so RenderIR remains usable without Active Support.
      def from_json(json) # rubocop:disable Rails/Delegate
        Document.from_json(json)
      end

      def canonical_json(value, **document_attributes)
        document = value.is_a?(Document) ? value : Document.new(root: value, **document_attributes)
        document.canonical_json
      end
    end
  end
end

require_relative 'render_ir/normalizer'
require_relative 'render_ir/record'
require_relative 'render_ir/modifier'
require_relative 'render_ir/node'
require_relative 'render_ir/document'
require_relative 'render_ir/patch_locator'
require_relative 'render_ir/patch_tree'
require_relative 'render_ir/patch_builder'
require_relative 'render_ir/patch_baseline'
