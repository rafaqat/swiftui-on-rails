# frozen_string_literal: true

require "application_system_test_case"

class StorybookProductPreviewTest < ApplicationSystemTestCase
  test "product-card preview launches its registered story" do
    visit rails_stories_path

    within "article[data-story-key='dsl_product_card']" do
      click_on "Open preview"
    end

    assert_current_path story_path(story: "dsl_product_card", story_variant: :default)

    within "#component-preview" do
      assert_selector "img[alt='Basic Tee in Black']"
      assert_text "$35"
      assert_selector "button", text: "Add to bag"
    end
  end
end
