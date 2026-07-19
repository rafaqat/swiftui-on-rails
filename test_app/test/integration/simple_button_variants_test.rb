# frozen_string_literal: true

require "test_helper"

class SimpleButtonVariantsTest < ActionDispatch::IntegrationTest
  test "button preview exposes its live scenario inventory" do
    get storybook_show_path,
        params: { story: "button_preview", story_variant: "primary_button" }

    assert_response :success
    assert_select "h2", text: "Preview Controls"
    assert_select "header h2", text: "Preview"
    assert_select "nav[aria-label='Story variants'] h2", text: "Variants"
    assert_select "[data-variant='primary_button']"
    assert_select "[data-variant='button_group']"
    assert_select "[data-variant='loading_state']"
  end

  test "primary button scenario renders one button" do
    get storybook_show_path,
        params: { story: "button_preview", story_variant: "primary_button" }

    assert_response :success
    assert_select "#component-preview button", count: 1, text: "Primary Button"
    assert_not_includes response.body, "Error rendering component:"
  end

  test "composed button scenarios render their expected controls" do
    {
      "button_group" => ["Save", "Save & Continue"],
      "loading_state" => ["Submit", "Processing..."],
      "toggle_button" => ["Grid View", "List View"]
    }.each do |variant, labels|
      get storybook_show_path,
          params: { story: "button_preview", story_variant: variant }

      assert_response :success
      assert_equal labels, css_select("#component-preview button").map { |button| button.text.strip }
      assert_not_includes response.body, "Error rendering component:"
    end
  end

  test "DSL button controls change the rendered button" do
    get storybook_show_path,
        params: {
          story: "dsl_button",
          story_variant: "default",
          text: "Custom Text",
          background_color: "red-600",
          size: "lg",
          disabled: "true"
        }

    assert_response :success
    assert_select "#component-preview button.bg-red-600[disabled]", count: 1, text: "Custom Text"
    assert_select "#component-preview button.px-6.py-3.text-lg"
    assert_not_includes response.body, "Error rendering component:"
  end
end
