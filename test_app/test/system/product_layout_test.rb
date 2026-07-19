# frozen_string_literal: true

require "application_system_test_case"

class ProductLayoutTest < ApplicationSystemTestCase
  test "product layout preserves semantic and responsive DSL structure" do
    visit storybook_show_path(story: "product_layout_simple")

    within "#component-preview" do
      assert_selector "section.min-h-screen"
      assert_selector ".max-w-7xl.mx-auto"
      assert_selector ".grid.grid-cols-1.sm\\:grid-cols-2.gap-6"
      assert_selector ".aspect-square.overflow-hidden", count: 4
      assert_selector "img.w-full.h-full.object-cover", count: 4
    end
  end
end
