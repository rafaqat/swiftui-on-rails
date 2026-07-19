# frozen_string_literal: true

require "application_system_test_case"

class ProductLayoutVisualTest < ApplicationSystemTestCase
  test "four-column layout renders sorting and the full product set" do
    visit storybook_show_path(story: "product_layout_simple", story_variant: "four_column_grid")

    within "#component-preview" do
      assert_text "Four Column Layout"
      assert_text "8 items"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3.xl\\:grid-cols-4.gap-6"
      assert_selector "select option[value='popular']", text: "Most Popular", visible: :all
      assert_selector "select option[value='price_asc']", text: "Price: Low to High", visible: :all
      assert_selector "img", count: 8
      assert_text "Leather Jacket"
      assert_text "$250"
    end
  end
end
