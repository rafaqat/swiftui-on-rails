# frozen_string_literal: true

require "application_system_test_case"

class ProductListDslE2eTest < ApplicationSystemTestCase
  test "responsive grid story renders every product through the nested helper" do
    visit storybook_show_path(story: "enhanced_grid", story_variant: "responsive_custom")

    within "#component-preview" do
      assert_text "Custom Responsive Grid"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.md\\:grid-cols-3.lg\\:grid-cols-4.xl\\:grid-cols-6"
      assert_selector "img", count: 12
      assert_selector "img[alt='Basic Tee']", minimum: 2
      assert_text "Canvas Tote"
      assert_text "$250"
    end

    assert_no_page_errors
  end

  test "asymmetric grid applies independent row and column gaps" do
    visit storybook_show_path(story: "enhanced_grid", story_variant: "asymmetric_gaps")

    within "#component-preview" do
      assert_text "Category Grid with Asymmetric Gaps"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3.gap-y-12.gap-x-4"
      assert_selector "button", text: "Browse", count: 6
      assert_text "245 products"
      assert_text "76 products"
    end
  end
end
