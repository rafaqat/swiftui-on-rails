# frozen_string_literal: true

module SwiftUIRails
  module Generators
    class StoriesGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)
      desc "Generate component stories (requires the optional ViewComponent Storybook integration)"

      RUBY_RESERVED_WORDS = %w[
        alias and begin break case class def defined do else elsif end ensure
        false for if in module next nil not or redo rescue retry return self
        super then true undef unless until when while yield
      ].freeze
      
      argument :stories, type: :array, default: [], banner: "story_name story_name"

      def ensure_storybook_available!
        return if SwiftUIRails.storybook_available? || SwiftUIRails.load_storybook

        raise Thor::Error,
          "SwiftUI Rails stories require a compatible gem that provides " \
          "`view_component/storybook`. Add `view_component-storybook`, run " \
          "`bundle install`, and retry this generator."
      end
      
      # SECURITY: Validate component name to prevent code injection
      def validate_component_name!
        unless name.match?(/\A[a-zA-Z][a-zA-Z0-9_]*\z/)
          raise Thor::Error, "Invalid component name '#{name}'. Component names must start with a letter and contain only letters, numbers, and underscores."
        end
        
        # Additional check for suspicious patterns
        if name.match?(/\b(system|exec|eval|constantize|send|public_send|instance_eval|class_eval|module_eval)\b/i)
          raise Thor::Error, "Component name '#{name}' contains forbidden keywords."
        end
      end
      
      def validate_story_names!
        stories.each do |story|
          unless story.match?(/\A[a-z_][a-z0-9_]*\z/)
            raise Thor::Error, "Invalid story name '#{story}'. Story names must start with a lowercase letter or underscore and contain only lowercase letters, numbers, and underscores."
          end

          if RUBY_RESERVED_WORDS.include?(story)
            raise Thor::Error, "Story name '#{story}' is a Ruby reserved word."
          end
          
          if story.match?(/\b(system|exec|eval)\b/i)
            raise Thor::Error, "Story name '#{story}' contains forbidden keywords."
          end
        end
      end
      
      def create_stories_file
        validate_component_name!
        validate_story_names!
        template "stories.rb.erb", File.join("test/components/stories", class_path, "#{file_name}_component_stories.rb")
      end
      
      def create_preview_file
        validate_component_name!
        validate_story_names!
        template "preview.html.erb", File.join("test/components/stories", class_path, "#{file_name}_component_preview.html.erb")
      end
      
      private
      
      def component_class_name
        # SECURITY: Ensure class name is safe
        sanitized_class_name = class_name.gsub(/[^A-Za-z0-9]/, '')
        "#{sanitized_class_name}Component"
      end
      
      def story_names
        # SECURITY: Sanitize story names
        validated_stories = stories.select { |story| valid_story_name?(story) }
        validated_stories.presence || ["default", "playground"]
      end

      def valid_story_name?(story)
        story.match?(/\A[a-z_][a-z0-9_]*\z/) &&
          !RUBY_RESERVED_WORDS.include?(story) &&
          !story.match?(/\b(system|exec|eval)\b/i)
      end
      
      def class_name
        # Override to ensure sanitization
        name.gsub(/[^A-Za-z0-9_]/, '').camelize
      end
      
      def file_name
        # Override to ensure safe file names
        name
          .gsub(/[^A-Za-z0-9_]+/, "_")
          .gsub(/\A_+|_+\z/, "")
          .underscore
      end
      
      def component_props
        component_class.swift_props rescue {}
      end
      
      def component_class
        # SECURITY: Safe constantize with validation
        class_name = component_class_name
        
        # Only allow valid component class names
        unless class_name.match?(/\A[A-Z][A-Za-z0-9]*Component\z/)
          return nil
        end
        
        # Additional safety check - ensure it's in the allowed namespace
        begin
          klass = class_name.constantize
          # Verify it's actually a component
          if defined?(ApplicationComponent) && klass < ApplicationComponent
            klass
          elsif defined?(ViewComponent::Base) && klass < ViewComponent::Base
            klass
          else
            nil
          end
        rescue NameError
          nil
        end
      end
      
      def default_prop_value(prop_config)
        value = if prop_config.key?(:default)
          prop_config[:default]
        else
          fallback_prop_value(prop_config[:type])
        end

        ruby_literal(value) || ruby_literal(fallback_prop_value(prop_config[:type])) || "nil"
      end

      def fallback_prop_value(type)
        case type&.to_s
        when "String"
          "Sample Text"
        when "Symbol"
          :default
        when "Integer", "Fixnum"
          42
        when "Float"
          3.14
        when "TrueClass", "FalseClass", "[TrueClass, FalseClass]"
          false
        when "Array"
          []
        when "Hash"
          {}
        end
      end

      def ruby_literal(value)
        case value
        when nil, true, false, String, Symbol, Integer
          value.inspect
        when Float
          return "Float::NAN" if value.nan?
          return value.positive? ? "Float::INFINITY" : "-Float::INFINITY" if value.infinite?

          value.inspect
        when Array
          values = value.map { |item| ruby_literal(item) }
          return if values.any?(&:nil?)

          "[#{values.join(', ')}]"
        when Hash
          pairs = value.map do |key, item|
            key_literal = ruby_literal(key)
            value_literal = ruby_literal(item)
            return unless key_literal && value_literal

            "#{key_literal} => #{value_literal}"
          end

          "{#{pairs.join(', ')}}"
        end
      end
    end
  end
end
