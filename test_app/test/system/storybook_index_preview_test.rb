# frozen_string_literal: true

require "application_system_test_case"

class StorybookIndexPreviewTest < ApplicationSystemTestCase
  test "catalog card exposes source-backed variants and a valid launch URL" do
    visit rails_stories_path

    assert_selector "h1", text: "Inspect the system, not screenshots."

    within "article[data-story-key='product_layout_simple']" do
      assert_selector "h3", text: "Product Catalog"
      assert_text "Collection rendering"
      assert_text(/\d+ variants?/)
      assert_link "Open preview →",
                  href: story_path(story: "product_layout_simple", story_variant: :default)
    end

    within "article[data-story-key='atlas_mission_control']" do
      assert_selector "h3", text: "Atlas Mission Control"
      assert_text "complete mission workspace"
      assert_link "Open preview →",
                  href: story_path(story: "atlas_mission_control", story_variant: :command_center)
    end
  end

  test "index categorizes all curated stories and gives each one a launch link" do
    visit rails_stories_path

    assert_selector "article[data-story-key]", count: StoryCatalog.entries.length
    assert_selector "section", minimum: 6
    assert_text "Complete interface compositions"
    assert_text "Platform explorations"
    assert_text "Workflows explorations"
    assert_text "Components explorations"
    assert_text "Layout explorations"
    assert_text "Patterns explorations"

    all("article[data-story-key]").each do |story|
      within story do
        assert_selector "h3"
        assert_selector "[aria-label='Available variants']"
        assert_link "Open preview →"
      end
    end
  end
end
