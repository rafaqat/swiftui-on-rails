# frozen_string_literal: true

require 'digest'
require 'json'

module SwiftUIRails
  module RenderIR
    # Assigns deterministic, DOM-safe locators to resolved element nodes. An
    # explicit semantic identity starts a new stable scope, so keyed collection
    # items keep their descendants when siblings move. Unidentified nodes use
    # their structural position, matching the usual positional reconciliation
    # semantics of declarative UI renderers.
    class PatchLocator
      ATTRIBUTE = 'data-swift-ui-ir-key'
      KEY_PATTERN = /\Asui-[0-9a-f]{24}\z/
      ROOT_SCOPE = 'swift-ui-rails.patch.v1'

      def self.for(document)
        new(document).call
      end

      def self.reactive?(document)
        document.is_a?(Document) && document.each_node.any? { |node| node.kind == 'reactive_container' }
      end

      def initialize(document)
        @document = document
        @locators = {}.compare_by_identity
      end

      def call
        return {}.freeze unless self.class.reactive?(@document)

        walk(@document.root, scope: ROOT_SCOPE, position: 0)
        @locators.freeze
      end

      private

      def walk(node, scope:, position:)
        if element?(node)
          basis = locator_basis(node, scope, position)
          @locators[node] = "sui-#{Digest::SHA256.hexdigest(basis).first(24)}".freeze
          child_scope = basis
        else
          child_scope = scope
        end

        node.children.each_with_index do |child, index|
          walk(child, scope: child_scope, position: index)
        end
      end

      def element?(node)
        %w[fragment text_literal trusted_html].exclude?(node.kind)
      end

      def locator_basis(node, scope, position)
        identity = stable_identity(node)
        segment = identity ? "identity\0#{identity}" : "position\0#{position}"
        "#{scope}\0#{segment}"
      end

      def stable_identity(node)
        return if node.identity.nil?

        JSON.generate(node.identity, max_nesting: false)
      end
    end
  end
end
