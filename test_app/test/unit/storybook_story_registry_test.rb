# frozen_string_literal: true

require "test_helper"

class StorybookStoryRegistryTest < ActiveSupport::TestCase
  test "registry includes every configured story file" do
    expected_names = Dir[Rails.root.join("test/components/stories/**/*_stories.rb")]
      .map { |file| File.basename(file, "_stories.rb") }
      .sort
    entries = StorybookStoryRegistry.all

    assert_equal expected_names, entries.map(&:name).sort
    assert entries.all? { |entry| entry.story_class < ViewComponent::Storybook::Stories }
    assert entries.all? { |entry| entry.variants.any? }
  end

  test "registry caches trusted entries without duplicating controls" do
    entry = StorybookStoryRegistry.fetch("dsl_card")
    control_count = entry.story_class.send(:controls).instance_variable_get(:@controls).length

    assert_same entry, StorybookStoryRegistry.fetch("dsl_card")

    StorybookStoryRegistry.reload!
    reloaded_entry = StorybookStoryRegistry.fetch("dsl_card")
    reloaded_control_count = reloaded_entry.story_class.send(:controls).instance_variable_get(:@controls).length

    assert_equal control_count, reloaded_control_count
    assert_includes reloaded_entry.variants, :default
    assert_nil StorybookStoryRegistry.fetch("../stories/dsl_card")
  end

  test "registry exposes every intended public button story variant" do
    entry = StorybookStoryRegistry.fetch("dsl_button")

    assert_equal %i[default interactive_showcase], entry.variants
    assert entry.story_class.public_method_defined?(:interactive_showcase)
  end

  test "registry variants follow source declaration order after reloads" do
    first_order = StorybookStoryRegistry.fetch("new_dsl_methods").variants

    StorybookStoryRegistry.reload!

    assert_equal %i[form_controls advanced_styling flex_and_styles], first_order
    assert_equal first_order, StorybookStoryRegistry.fetch("new_dsl_methods").variants
  end

  test "story sessions resolve live stories and variants through the registry" do
    session = StorySession.new(
      story_name: "dsl_card",
      variant: "default",
      session_id: "registry-test"
    )

    assert_equal "StoryHtmlWrapperComponent", session.component_instance.class.name

    invalid_variant = StorySession.new(
      story_name: "dsl_card",
      variant: "public_send",
      session_id: "registry-test"
    )
    assert_raises(SwiftUIRails::SecurityError) { invalid_variant.component_instance }
  end
end
