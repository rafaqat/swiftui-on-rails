# frozen_string_literal: true

# Discovers Storybook stories from application-configured, trusted directories.
# Request parameters are only ever used as keys into this registry; they never
# participate in file paths or constant lookup.
class StorybookStoryRegistry
  Entry = Data.define(
    :name,
    :file,
    :story_class,
    :component_name,
    :component_class,
    :variants
  )

  class << self
    def fetch(name)
      entries[name.to_s]
    end

    def all
      entries.values
    end

    def reload!
      @entries = nil
    end

    private

    def entries
      @entries ||= build_entries.freeze
    end

    def build_entries
      story_files.each_with_object({}) do |file, registry|
        require_dependency file

        story_name = File.basename(file, "_stories.rb")
        story_class_name = "#{story_name.camelize}Stories"
        story_class = story_class_name.safe_constantize
        unless valid_story_class?(story_class)
          raise NameError,
                "#{file} must define #{story_class_name} as a ViewComponent::Storybook::Stories subclass"
        end
        # safe_constantize can resolve an already-loaded same-named class from a
        # different file; require that this file actually defines it so we never
        # register the wrong class (and its variants) under this story name.
        definition_file = Object.const_source_location(story_class_name)&.first
        unless definition_file && File.expand_path(definition_file) == File.expand_path(file)
          raise NameError,
                "#{file} must define #{story_class_name}, but it resolves to " \
                "#{definition_file || 'an unknown location'}"
        end
        if registry.key?(story_name)
          raise ArgumentError, "Duplicate Storybook story name: #{story_name}"
        end

        base_name = story_name.sub(/_component\z/, "")
        component_name = "#{base_name}_component"
        component_class = component_name.camelize.safe_constantize
        variants = story_class.public_instance_methods(false)
          .map(&:to_sym)
          .sort_by do |variant|
            source_location = story_class.instance_method(variant).source_location
            [source_location&.last || Float::INFINITY, variant.to_s]
          end
          .freeze
        raise ArgumentError, "Storybook story has no public variants: #{story_name}" if variants.empty?

        registry[story_name] = Entry.new(
          name: story_name,
          file: Pathname.new(file),
          story_class: story_class,
          component_name: component_class ? component_name : story_name,
          component_class: component_class,
          variants: variants
        )
      end
    end

    def story_files
      configured_story_paths.flat_map do |path|
        Dir.glob(File.join(File.expand_path(path.to_s), "**", "*_stories.rb"))
      end.uniq.sort
    end

    def configured_story_paths
      direct_paths = Array(ViewComponent::Storybook.stories_paths)
      configurable_paths = if ViewComponent::Storybook.respond_to?(:config)
        Array(ViewComponent::Storybook.config.stories_paths)
      else
        []
      end

      (direct_paths + configurable_paths).compact.uniq
    end

    def valid_story_class?(story_class)
      story_class.is_a?(Class) && story_class < ViewComponent::Storybook::Stories
    end
  end
end
