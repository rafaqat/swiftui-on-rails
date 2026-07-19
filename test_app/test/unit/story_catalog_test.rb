# frozen_string_literal: true

require "test_helper"

# Guards the contract between the curated StoryCatalog (presentation) and the
# StorybookStoryRegistry (discovery). A story that is registered but neither
# cataloged nor explicitly unlisted would silently vanish from the index page;
# a catalog entry without a registered story is a dead card.
class StoryCatalogTest < ActiveSupport::TestCase
  test "every catalog entry resolves to a registered story" do
    StoryCatalog.entries.each do |entry|
      registry_entry = StorybookStoryRegistry.fetch(entry.fetch(:path))
      assert registry_entry, "Catalog entry #{entry[:path]} has no registered story file"
    end
  end

  test "every catalog default variant exists on its story" do
    StoryCatalog.entries.each do |entry|
      registry_entry = StorybookStoryRegistry.fetch(entry.fetch(:path))
      next unless registry_entry

      assert_includes registry_entry.variants, entry.fetch(:default_variant),
                      "Catalog entry #{entry[:path]}: default_variant #{entry[:default_variant]} is not a story variant"
    end
  end

  test "every registered story is cataloged or explicitly unlisted" do
    cataloged = StoryCatalog.entries.map { |entry| entry.fetch(:path) }

    StorybookStoryRegistry.all.each do |registry_entry|
      name = registry_entry.name
      assert cataloged.include?(name) || StoryCatalog::UNLISTED_STORIES.include?(name),
             "Story #{name} is registered but neither cataloged nor in StoryCatalog::UNLISTED_STORIES"
    end
  end

  test "catalog paths are unique" do
    paths = StoryCatalog.entries.map { |entry| entry.fetch(:path) }
    assert_equal paths.uniq, paths
  end

  test "source display defaults to true for cataloged stories and false for unknown ones" do
    assert StoryCatalog.source_display?("dsl_button")
    assert_not StoryCatalog.source_display?("counter_component")
    assert_not StoryCatalog.source_display?("not_a_story")
  end

  test "flagship DSL surfaces display source from their backing components" do
    assert StoryCatalog.source_from_component?("atlas_mission_control")
    assert StoryCatalog.source_from_component?("swift_ui_rails_playground")
    assert_not StoryCatalog.source_from_component?("dsl_button")
  end
end
