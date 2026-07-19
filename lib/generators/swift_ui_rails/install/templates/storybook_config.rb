# frozen_string_literal: true

if defined?(ViewComponent::Storybook)
  ViewComponent::Storybook.configure do |config|
    # Where to find component stories
    config.stories_paths = [Rails.root.join("test/components/stories")]
    
    # Story titles use component names
    config.stories_title_generator = lambda do |story_class|
      story_class.name.chomp("Stories").titleize
    end
  end
  
  # Add the SwiftUI Rails DSL and rendering helpers to all stories. Storybook
  # itself is a class, so it must not be passed to Ruby's `include`.
  if defined?(SwiftUIRails::Storybook::Helpers)
    ViewComponent::Storybook::Stories.include SwiftUIRails::Storybook::Helpers
  end
  
  # Configure preview layouts
  Rails.application.config.to_prepare do
    if ViewComponent::Storybook.respond_to?(:stories_layout=)
      ViewComponent::Storybook.stories_layout = "storybook"
    end
  end
end
