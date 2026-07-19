# frozen_string_literal: true

require 'json'
require 'set'

module SwiftUIRails
  module RenderIR
    # Produces a bounded v1 keyed DOM patch. Child order is reconciled with a
    # longest-increasing-subsequence pass, minimizing move operations while
    # retaining a deterministic operation order.
    class PatchBuilder # rubocop:disable Metrics/ClassLength
      VERSION = 1
      MAX_OPERATIONS = 512
      MAX_PATCH_BYTES = 256.kilobytes

      class UnsafeDiff < SwiftUIRails::RenderIR::Error; end
      class BudgetExceeded < SwiftUIRails::RenderIR::Error; end

      # Immutable outcome returned to the reactive endpoint. A fallback carries
      # no operations so callers cannot accidentally serialize a partial plan.
      class Result
        attr_reader :operations, :reason

        def initialize(operations:, reason: nil)
          @operations = operations.map(&:freeze).freeze
          @reason = reason&.to_sym
          freeze
        end

        def patch?
          reason.nil?
        end

        def fallback?
          !patch?
        end

        def to_h(component_id:)
          raise UnsafeDiff, "cannot serialize a fallback patch (#{reason})" if fallback?

          {
            'component_id' => component_id.to_s,
            'operations' => operations,
            'version' => VERSION
          }
        end
      end

      def self.call(old_tree:, new_tree:, full_html:)
        new(old_tree: old_tree, new_tree: new_tree, full_html: full_html).call
      end

      def initialize(old_tree:, new_tree:, full_html:)
        @old_tree = old_tree
        @new_tree = new_tree
        @full_html = full_html.to_s
        @operations = []
      end

      def call
        validate_inputs!
        diff_element(@old_tree.root, @new_tree.root)
        patch_bytes = serialized_patch_bytes
        return fallback(:budget_exceeded) if patch_bytes > MAX_PATCH_BYTES
        return fallback(:patch_not_smaller) unless patch_bytes < @full_html.bytesize

        Result.new(operations: @operations)
      rescue UnsafeDiff => e
        fallback(e.message)
      rescue BudgetExceeded
        fallback(:budget_exceeded)
      end

      private

      def validate_inputs!
        raise UnsafeDiff, :invalid_tree unless @old_tree.is_a?(PatchTree) && @new_tree.is_a?(PatchTree)
        raise UnsafeDiff, :root_changed unless @old_tree.root.key == @new_tree.root.key
        raise UnsafeDiff, :empty_full_html if @full_html.empty?
      end

      # Branches map one-to-one to the deliberately small patch protocol.
      def diff_element(old_element, new_element) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        return if old_element.equivalent?(new_element)
        raise UnsafeDiff, :key_changed unless old_element.key == new_element.key

        if old_element.tag != new_element.tag || replace_for_mixed_content?(old_element, new_element)
          raise UnsafeDiff, 'root_replace_required' if root_element?(new_element)

          add_operation(replace_operation(new_element))
          return
        end

        if old_element.attributes != new_element.attributes
          add_operation(
            'attributes' => new_element.attributes,
            'key' => new_element.key,
            'op' => 'attributes'
          )
        end

        old_children = old_element.children
        new_children = new_element.children
        if old_children.empty? && new_children.empty?
          add_text_operation(new_element) if old_element.text != new_element.text
          return
        end

        if old_children.empty? || new_children.empty?
          raise UnsafeDiff, 'root_replace_required' if root_element?(new_element)

          replace_last_operations_for(new_element)
          return
        end

        reconcile_children(old_element, new_element)
      end

      def replace_for_mixed_content?(old_element, new_element)
        old_mixed = mixed_text?(old_element)
        new_mixed = mixed_text?(new_element)
        return false unless old_mixed || new_mixed

        old_element.content != new_element.content
      end

      def mixed_text?(element)
        element.children.any? && element.content.any? do |kind, value|
          kind == 'text' && !value.empty?
        end
      end

      def add_text_operation(element)
        add_operation('key' => element.key, 'op' => 'text', 'value' => element.text.to_s)
      end

      # The keyed reconciliation phases are intentionally kept together so
      # remove, order, insertion, and recursive diff ordering stays obvious.
      def reconcile_children(old_parent, new_parent) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        old_by_key = old_parent.children.index_by(&:key)
        new_by_key = new_parent.children.index_by(&:key)
        old_keys = old_parent.children.map(&:key)
        new_keys = new_parent.children.map(&:key)

        (old_keys - new_keys).each do |key|
          add_operation('key' => key, 'op' => 'remove')
        end

        stable_keys = longest_stable_subsequence(old_keys, new_keys)
        before_key = nil
        new_parent.children.reverse_each do |child|
          if old_by_key.key?(child.key)
            unless stable_keys.include?(child.key)
              add_operation(
                'before_key' => before_key,
                'key' => child.key,
                'op' => 'move',
                'parent_key' => new_parent.key
              )
            end
          else
            add_operation(
              'before_key' => before_key,
              'html' => required_html(child),
              'op' => 'insert',
              'parent_key' => new_parent.key
            )
          end
          before_key = child.key
        end

        new_parent.children.each do |child|
          previous = old_by_key[child.key]
          diff_element(previous, child) if previous && new_by_key.key?(child.key)
        end
      end

      # Returns the common keys whose old positions form an LIS in new order.
      # O(n log n) patience-sorting implementation of the LIS.
      def longest_stable_subsequence(old_keys, new_keys) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        old_positions = old_keys.each_with_index.to_h
        common = new_keys.filter_map do |key|
          position = old_positions[key]
          [key, position] if position
        end
        return Set.new if common.empty?

        tails = []
        tail_indexes = []
        previous = Array.new(common.length)

        common.each_with_index do |(_key, position), index|
          slot = lower_bound(tails, position)
          tails[slot] = position
          previous[index] = slot.positive? ? tail_indexes[slot - 1] : nil
          tail_indexes[slot] = index
        end

        stable = Set.new
        cursor = tail_indexes[tails.length - 1]
        while cursor
          stable.add(common[cursor].first)
          cursor = previous[cursor]
        end
        stable
      end

      def lower_bound(values, target)
        left = 0
        right = values.length
        while left < right
          middle = (left + right) / 2
          if values[middle] < target
            left = middle + 1
          else
            right = middle
          end
        end
        left
      end

      # Supersede only the attributes op emitted earlier in this same
      # diff_element call. Scoping to op == 'attributes' is essential: the
      # parent's reconcile_children may have already emitted a 'move' for this
      # key, and dropping it would leave the replaced element at its old DOM
      # position (a keyed element that both reorders and transitions between
      # leaf and parent in one diff).
      # Supersede only the attributes op emitted earlier in this same
      # diff_element call. Scoping to op == 'attributes' is essential: the
      # parent's reconcile_children may have already emitted a 'move' for this
      # key, and dropping it would leave the replaced element at its old DOM
      # position (a keyed element that both reorders and transitions between
      # leaf and parent in one diff).
      def replace_last_operations_for(element)
        @operations.reject! do |operation|
          operation['key'] == element.key && operation['op'] == 'attributes'
        end
        add_operation(replace_operation(element))
      end

      def root_element?(element)
        element.key == @new_tree.root.key
      end

      def replace_operation(element)
        { 'html' => required_html(element), 'key' => element.key, 'op' => 'replace' }
      end

      def required_html(element)
        value = element.html
        raise UnsafeDiff, :current_html_missing unless value.is_a?(String) && !value.empty?

        value
      end

      def add_operation(operation)
        @operations << operation
        return unless @operations.length > MAX_OPERATIONS

        raise BudgetExceeded.new('Patch exceeds its operation budget.', path: '$.operations')
      end

      def serialized_patch_bytes
        component_id = @new_tree.root.attributes.fetch('id', '')
        JSON.generate('component_id' => component_id, 'operations' => @operations, 'version' => VERSION).bytesize
      end

      def fallback(reason)
        Result.new(operations: [], reason: reason)
      end
    end
  end
end
