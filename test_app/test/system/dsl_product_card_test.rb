# frozen_string_literal: true

require "application_system_test_case"

class DslProductCardTest < ApplicationSystemTestCase
  test "product card story renders image, details, and CTA" do
    visit storybook_show_path(story: "dsl_product_card", story_variant: "default")

    within "#component-preview" do
      assert_selector ".max-w-sm"
      assert_selector "img[alt='Basic Tee in Black'][src*='product-page-01-related-product-04.jpg']"
      assert_text "Basic Tee"
      assert_text "Black"
      assert_text "$35"
      assert_selector "button", text: "Add to bag"
    end

    assert_no_page_errors
    assert_no_console_errors
  end
end
