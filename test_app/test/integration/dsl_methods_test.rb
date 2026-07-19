# frozen_string_literal: true

require "test_helper"

class DslMethodsTest < ActionDispatch::IntegrationTest
  test "form-control DSL methods render through the live Storybook route" do
    get storybook_show_path,
        params: {
          story: "new_dsl_methods",
          story_variant: "form_controls",
          selected_color: "green",
          show_label: "true",
          label_text: "Pick one"
        }

    assert_response :success
    assert_select "#component-preview label[for='color-select']", text: "Pick one"
    assert_select "#component-preview select[name='color'] option[value='green'][selected='selected']"
    assert_not_includes response.body, "Error rendering component:"
  end

  test "advanced styling controls produce their requested utility classes" do
    get storybook_show_path,
        params: {
          story: "new_dsl_methods",
          story_variant: "advanced_styling",
          break_mode: "avoid-page",
          ring_width: "4",
          ring_color: "purple-500",
          group_opacity: "50"
        }

    assert_response :success
    assert_includes response.body, "break-inside-avoid-page"
    assert_includes response.body, "hover:ring-4"
    assert_includes response.body, "hover:ring-purple-500"
    assert_includes response.body, "group-hover:opacity-50"
    assert_not_includes response.body, "Error rendering component:"
  end

  test "flex and inline-style modifiers render from live controls" do
    get storybook_show_path,
        params: {
          story: "new_dsl_methods",
          story_variant: "flex_and_styles",
          flex_shrink_value: "0",
          custom_style: "color: red;",
          tooltip_text: "Custom tooltip"
        }

    assert_response :success
    assert_select "#component-preview .flex-shrink-0"
    assert_select "#component-preview [title='Custom tooltip'][style*='color: red']"
    assert_not_includes response.body, "Error rendering component:"
  end

  test "line clamp is exercised by a current story instead of a missing fixture" do
    get storybook_show_path,
        params: {
          story: "dsl_card",
          story_variant: "default",
          card_content: "This content should be clamped"
        }

    assert_response :success
    assert_select "#component-preview .line-clamp-3", text: "This content should be clamped"
    assert_not_includes response.body, "Error rendering component:"
  end

  test "image and alignment modifiers render in the enhanced grid story" do
    get storybook_show_path,
        params: { story: "enhanced_grid", story_variant: "dense_packing" }

    assert_response :success
    assert_select "#component-preview .aspect-square"
    assert_select "#component-preview .object-cover"
    assert_select "#component-preview .text-center"
    assert_not_includes response.body, "Error rendering component:"
  end
end
