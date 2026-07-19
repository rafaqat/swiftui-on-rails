# frozen_string_literal: true

require "application_system_test_case"

class DslCollectionRenderingTest < ApplicationSystemTestCase
  test "nested DSL product helpers render every collection item" do
    visit storybook_show_path(story: "product_layout_simple")

    within "#component-preview" do
      assert_text "Product Catalog"
      assert_text "4 items"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.gap-6"
      assert_selector "img", count: 4
      assert_selector "button", text: "Add to Cart", count: 4
      assert_selector "img[alt='Nomad Tumbler']"
      assert_selector "img[alt='Travel Mug']"
    end

    assert_no_page_errors
  end
end
