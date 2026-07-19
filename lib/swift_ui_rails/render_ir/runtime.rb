# frozen_string_literal: true

require_relative 'capability_registry'
require_relative 'value_codec'
require_relative 'attribute_policy'
require_relative 'validator'
require_relative 'html_renderer'
require_relative 'runtime_node_factory'
require_relative 'session'

module SwiftUIRails
  module RenderIR
    # Lowers the existing mutable DSL Element into one immutable resolved node.
    # This module is prepended after every Element extension has loaded, making
    # RenderIR the sole live HTML path without executing a second shadow tree.
    module ElementLowering # rubocop:disable Metrics/ModuleLength
      PAIRED_EMPTY_TAGS = %w[span p h1 h2 h3 h4 h5 h6 div label button].freeze

      attr_writer :swift_ui_semantic_kind

      def to_render_ir(session = nil)
        active_session = session || Session.new(view_context: render_ir_view_context)
        if defined?(Environment) && @swift_ui_environment_overrides&.any?
          Environment.with(@swift_ui_environment_overrides) { lower_element(active_session) }
        else
          lower_element(active_session)
        end
      end

      def to_s # rubocop:disable Metrics/AbcSize
        session = Session.new(view_context: render_ir_view_context)
        document = session.document(children: [to_render_ir(session)], component: render_ir_component)
        rendered = session.render(document)
        record_render_ir(document, rendered_html: rendered, session: session)
        rendered
      rescue StandardError => e
        Rails.logger.error "Element RenderIR failed: #{e.message} for tag #{@tag_name.inspect}"
        Rails.logger.error e.backtrace.join("\n") if e.backtrace
        raise
      end

      def to_str
        to_s
      end

      private

      def lower_element(session) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        if Rails.logger.debug?
          Rails.logger.debug do
            "Element.to_s: tag=#{@tag_name}, has_block=#{!@block.nil?}, content_present=#{!@content.nil?}"
          end
        end
        merge_render_attributes!
        register_render_actions!

        child_nodes = if @block
                        lower_block_children(session)
                      elsif @content
                        [lower_content(@content, session)]
                      else
                        Node::EMPTY_ARRAY
                      end
        tag_name = @tag_name.to_s

        RuntimeNodeFactory.element(
          kind: render_ir_kind(tag_name),
          tag: tag_name,
          attribute_pairs: render_attribute_pairs,
          # The IR schema requires an actual boolean, not the truthy block or content object.
          paired: !!(@block || @content || PAIRED_EMPTY_TAGS.include?(tag_name)), # rubocop:disable Style/DoubleNegation
          modifiers: render_ir_modifiers,
          children: child_nodes,
          identity: render_ir_identity,
          accessibility: render_ir_accessibility
        )
      end

      def merge_render_attributes!
        if @css_classes&.any?
          existing_classes = @options[:class] || ''
          classes = (existing_classes.split + @css_classes).uniq.compact_blank.join(' ')
          @options[:class] = classes
        end
        @options.merge!(@attributes) if @attributes
      end

      def render_attribute_pairs
        return Node::EMPTY_ARRAY if @options.empty?

        @options.map.with_index do |(name, value), index|
          [
            name.to_s,
            ValueCodec.encode(value, path: "$.props.attribute_pairs[#{index}][1]")
          ]
        end
      end

      def register_render_actions!
        return unless @action_blocks && @view_context.respond_to?(:register_component_action)

        @action_blocks.each do |action_id, action|
          @view_context.register_component_action(action_id, action)
        end
      end

      def lower_block_children(session)
        if @dsl_context
          lower_context_block(session)
        else
          lower_standalone_block(session)
        end
      end

      def lower_context_block(session)
        sub_context = SwiftUIRails::DSLContext.new(@dsl_context, layout_axis: @child_layout_axis)
        component = @dsl_context.instance_variable_get(:@component) || @component
        sub_context.instance_variable_set(:@component, component) if component

        result = sub_context.instance_eval(&@block)
        register_returned_elements(sub_context, result)
        children = sub_context.consume_render_ir_nodes(session)
        append_context_block_result(children, result, sub_context, session)
      end

      def register_returned_elements(context, result)
        pending = context.instance_variable_get(:@pending_elements)
        if result.is_a?(SwiftUIRails::DSL::Element)
          context.register_element(result) unless pending.include?(result)
        elsif result.is_a?(Array)
          result.grep(SwiftUIRails::DSL::Element).each do |element|
            context.register_element(element) unless pending.include?(element)
          end
        end
      end

      def append_context_block_result( # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        children, result, context, session
      )
        if result.respond_to?(:to_str) && !result.is_a?(SwiftUIRails::DSL::Element)
          children << lower_content(result, session) unless context.rendered_child?(result)
        elsif result.is_a?(Array) || result.is_a?(SwiftUIRails::DSL::Element)
          # Enumerable return values are control-flow data. Element values have
          # already been registered and lowered above.
        elsif !result.nil?
          rendered = result.to_s
          children << session.trusted_html(rendered) if rendered.respond_to?(:html_safe?) && rendered.html_safe?
        end
        children
      end

      def lower_standalone_block(session)
        target = render_ir_view_context
        result = if target.respond_to?(:capture)
                   target.capture { safe_block_result(@block.call) }
                 else
                   @block.call
                 end
        values = result.is_a?(Array) ? result : [result]
        values.compact.map do |value|
          if value.is_a?(SwiftUIRails::DSL::Element)
            value.to_render_ir(session)
          else
            lower_content(value, session)
          end
        end
      end

      def lower_content(value, session)
        if value.is_a?(SwiftUIRails::DSL::Element)
          value.to_render_ir(session)
        elsif value.respond_to?(:html_safe?) && value.html_safe?
          session.trusted_html(value)
        else
          session.text(value)
        end
      end

      def render_ir_modifiers
        return Node::EMPTY_ARRAY if @swift_ui_ir_modifiers.blank?

        Array(@swift_ui_ir_modifiers).map do |modifier|
          modifier.is_a?(Modifier) ? modifier : Modifier.new(**modifier)
        end
      end

      def render_ir_kind(tag_name)
        candidate = @swift_ui_semantic_kind ? @swift_ui_semantic_kind.to_s : tag_name
        return candidate if candidate.match?(/\A[a-z][a-z0-9_]*\z/)

        candidate = candidate.downcase.gsub(/[^a-z0-9_]/, '_')
        candidate.match?(/\A[a-z]/) ? candidate : 'element'
      end

      def render_ir_identity
        value = @options['id'] || @options[:id] || @options['data-morph-id'] || @options[:'data-morph-id']
        value.nil? ? nil : ValueCodec.encode(value, path: '$.identity')
      end

      def render_ir_accessibility # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        result = nil
        @options.each do |name, value|
          key = name.to_s
          if key == 'aria' && value.is_a?(Hash)
            value.each do |aria_name, aria_value|
              flattened = "aria-#{aria_name.to_s.tr('_', '-')}"
              (result ||= {})[flattened] = ValueCodec.encode(
                aria_value,
                path: "$.accessibility.#{flattened}"
              )
            end
          elsif key == 'role' || key.start_with?('aria-')
            (result ||= {})[key] = ValueCodec.encode(value, path: "$.accessibility.#{key}")
          end
        end
        result || Node::EMPTY_HASH
      end

      def render_ir_view_context
        if @dsl_context.respond_to?(:render_target)
          @dsl_context.render_target
        elsif @view_context.is_a?(SwiftUIRails::DSLContext)
          @view_context.render_target
        else
          @view_context
        end
      end

      def render_ir_component
        @component || @dsl_context&.component
      end

      def record_render_ir(document, rendered_html: nil, session: nil)
        component = render_ir_component
        return unless component.respond_to?(:record_render_ir)

        component.record_render_ir(document, rendered_html: rendered_html, session: session)
      end
    end

    # RawElement is the explicit compatibility boundary for already-rendered
    # trusted HTML. The HTML stays in the request-local registry.
    module RawElementLowering
      def to_render_ir(session = nil)
        active_session = session || Session.new(view_context: render_ir_view_context)
        if @raw_html.respond_to?(:html_safe?) && @raw_html.html_safe?
          active_session.trusted_html(@raw_html)
        else
          active_session.text(@raw_html)
        end
      end

      def to_s
        session = Session.new(view_context: render_ir_view_context)
        session.render(session.document(children: [to_render_ir(session)]))
      end

      def to_str
        to_s
      end
    end

    # DSLContext owns the single compile -> validate -> render transaction.
    module ContextLowering
      attr_reader :last_render_ir

      def render_target
        context = view_context
        context = context.view_context while context.is_a?(SwiftUIRails::DSLContext)
        context
      end

      def consume_render_ir_nodes(session = render_ir_session)
        nodes = @pending_elements.map do |element|
          element.view_context ||= view_context
          element.to_render_ir(session)
        end
        @pending_elements.clear
        nodes
      end

      def flush_elements
        session = render_ir_session
        nodes = consume_render_ir_nodes(session)
        nodes = Array(yield(nodes, session)) if block_given?
        document = session.document(children: nodes, component: component)
        rendered = session.render(document)
        @last_render_ir = document
        if component.respond_to?(:record_render_ir)
          component.record_render_ir(document, rendered_html: rendered, session: session)
        end
        rendered
      end

      private

      def render_ir_session
        render_state[:render_ir_session] ||= Session.new(view_context: render_target)
      end
    end

    # Exposes the complete document produced by a component's latest render to
    # linting, development tools, and tests without making it persisted state.
    module ComponentIntrospection
      attr_reader :last_render_ir

      def record_render_ir(document, rendered_html: nil, session: nil)
        @last_render_ir = document
        @last_render_ir_session = session
        return unless respond_to?(:store_reactive_patch_baseline, true)

        store_reactive_patch_baseline(document, rendered_html: rendered_html)
      end
    end

    # Captures the outer semantic builder (vstack, chart, toolbar, etc.) before
    # it resolves to a concrete web tag. Internal builder-to-builder calls keep
    # the outermost vocabulary term.
    module Instrumentation
      ELEMENT_EXCLUSIONS = %i[
        content html_safe? method_missing options respond_to_missing? tag_name
        to_render_ir to_s to_str view_context view_context= child_layout_axis
        child_layout_axis= swift_ui_semantic_kind=
      ].freeze

      module_function

      def install!
        install_builder_tracking!
        install_modifier_tracking!
        install_runtime_lowering!
      end

      def modifier_record(method_name, arguments, keywords) # rubocop:disable Metrics/AbcSize
        if method_name.to_sym == :environment
          environment_keys = Array(arguments.first.is_a?(Hash) ? arguments.first.keys : arguments.first)
          environment_keys.concat(keywords.keys)
          return {
            name: method_name.to_s,
            arguments: [],
            keywords: { 'keys' => environment_keys.compact.map(&:to_s).uniq.sort }
          }
        end

        {
          name: method_name.to_s,
          arguments: ValueCodec.encode_modifier_arguments(arguments),
          keywords: ValueCodec.encode_modifier_keywords(keywords)
        }
      end

      # Dynamic wrappers preserve the exact public builder vocabulary while
      # recording only the outermost semantic builder name.
      def install_builder_tracking! # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        return if SwiftUIRails::DSL.const_defined?(:RenderIRBuilderTracking, false)

        builder_methods = SwiftUIRails::DSL.public_instance_methods(false)
        tracking = Module.new
        builder_methods.each do |method_name|
          tracking.define_method(method_name) do |*args, **kwargs, &block|
            previous = instance_variable_get(:@_swift_ui_semantic_builder)
            instance_variable_set(:@_swift_ui_semantic_builder, method_name) unless previous
            super(*args, **kwargs, &block)
          ensure
            if previous
              instance_variable_set(:@_swift_ui_semantic_builder, previous)
            elsif instance_variable_defined?(:@_swift_ui_semantic_builder)
              remove_instance_variable(:@_swift_ui_semantic_builder)
            end
          end
        end

        element_capture = Module.new do
          private

          def create_element(*args, **kwargs, &block)
            element = super
            semantic_kind = instance_variable_get(:@_swift_ui_semantic_builder)
            element.swift_ui_semantic_kind = semantic_kind if semantic_kind
            element
          end
        end

        SwiftUIRails::DSL.const_set(:RenderIRBuilderTracking, tracking)
        SwiftUIRails::DSL.const_set(:RenderIRElementCapture, element_capture)
        SwiftUIRails::DSL.prepend(element_capture)
        SwiftUIRails::DSL.prepend(tracking)
      end

      # Modifier methods are discovered after all extensions load. The wrapper
      # records only the outermost fluent call and restores nesting on errors.
      def install_modifier_tracking! # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        element_class = SwiftUIRails::DSL::Element
        return if element_class.const_defined?(:RenderIRModifierTracking, false)

        candidate_methods = element_class.public_instance_methods.select do |method_name|
          owner_name = element_class.instance_method(method_name).owner.name.to_s
          owner_name.start_with?('SwiftUIRails::') && ELEMENT_EXCLUSIONS.exclude?(method_name)
        end

        tracking = Module.new
        candidate_methods.each do |method_name|
          tracking.define_method(method_name) do |*args, **kwargs, &block|
            depth = instance_variable_get(:@_swift_ui_modifier_depth).to_i
            instance_variable_set(:@_swift_ui_modifier_depth, depth + 1)
            result = super(*args, **kwargs, &block)
            if depth.zero? && result.equal?(self)
              @swift_ui_ir_modifiers ||= []
              @swift_ui_ir_modifiers << SwiftUIRails::RenderIR::Instrumentation.modifier_record(
                method_name,
                args,
                kwargs
              )
            end
            result
          ensure
            if depth.zero?
              if instance_variable_defined?(:@_swift_ui_modifier_depth)
                remove_instance_variable(:@_swift_ui_modifier_depth)
              end
            else
              instance_variable_set(:@_swift_ui_modifier_depth, depth)
            end
          end
        end

        element_class.const_set(:RenderIRModifierTracking, tracking)
        element_class.prepend(tracking)
      end

      def install_runtime_lowering!
        SwiftUIRails::DSL::Element.prepend(ElementLowering)
        SwiftUIRails::DSL::RawElement.prepend(RawElementLowering)
        SwiftUIRails::DSLContext.prepend(ContextLowering)
        SwiftUIRails::Component::Base.include(ComponentIntrospection)
      end
    end
  end
end

SwiftUIRails::RenderIR::Instrumentation.install!
