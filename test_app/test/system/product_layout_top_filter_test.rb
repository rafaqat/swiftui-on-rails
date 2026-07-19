# frozen_string_literal: true

require "application_system_test_case"

class ProductLayoutTopFilterTest < ApplicationSystemTestCase
  test "filtered product layout renders controls above all products" do
    visit storybook_show_path(story: "product_layout_simple", story_variant: "with_filters")

    within "#component-preview" do
      assert_text "Filtered Products"
      assert_text "8 items"
      assert_selector ".bg-white.p-6.rounded-lg.shadow-sm"
      assert_selector "button", text: "All"
      assert_selector "button", text: "Shirts"
      assert_selector "button", text: "Accessories"
      assert_selector "button", text: "Outerwear"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3.gap-6"
      assert_selector "img", count: 8
      assert_selector "button", text: "Add to Cart", count: 8
    end

    assert_no_page_errors
  end
end
