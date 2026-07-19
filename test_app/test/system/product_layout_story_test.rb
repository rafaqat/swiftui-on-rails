# frozen_string_literal: true

require "application_system_test_case"

class ProductLayoutStoryTest < ApplicationSystemTestCase
  test "default product layout story renders its complete catalog" do
    visit storybook_show_path(story: "product_layout_simple", story_variant: "default")

    within "#component-preview" do
      assert_text "Product Catalog"
      assert_text "4 items"
      assert_selector "img", count: 4
      assert_selector "button", text: "Add to Cart", count: 4
      assert_text "Nomad Tumbler"
      assert_text "$25"
    end

    assert_no_page_errors
  end

  test "storybook exposes each registered product layout variant" do
    visit storybook_show_path(story: "product_layout_simple")

    assert_selector "[data-variant='default']"
    assert_selector "[data-variant='with_filters']"
    assert_selector "[data-variant='four_column_grid']"
  end
end
