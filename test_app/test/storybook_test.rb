# frozen_string_literal: true

require "test_helper"

class StorybookTest < ActionDispatch::IntegrationTest
  test "canonical catalog is reachable and links only registered stories" do
    get rails_stories_path

    assert_response :success
    assert_select "h1", text: /Inspect the system, not screenshots/
    assert_select "article[data-story-key]", count: StoryCatalog.entries.length
    assert_select "a", text: "Open preview →", count: StoryCatalog.entries.length
  end

  test "button story renders explicit controls and preview" do
    get story_path("dsl_button")

    assert_response :success
    assert_select "h1", "Dsl Button"
    assert_select "h2", text: /Preview Controls/
    assert_select "h2", text: /Preview/
    assert_select "input[name='text'][value='Click Me']"
    assert_select "#component-preview button", text: "Click Me"
  end

  test "registered variants are selected only through trusted links" do
    entry = StorybookStoryRegistry.fetch("dsl_button")
    assert_equal %i[default interactive_showcase], entry.variants.sort

    get story_path("dsl_button", story_variant: "interactive_showcase")

    assert_response :success
    entry.variants.each do |variant|
      assert_select "a[data-variant='#{variant}']", text: variant.to_s.humanize, count: 1
    end
    assert_select "a[data-variant='interactive_showcase'][aria-current='page']", count: 1
    assert_select "#component-preview", text: /Interactive DSL Button Showcase/
  end

  test "GET parameters render into the selected story" do
    get story_path(
      "dsl_button",
      story_variant: "default",
      text: "Ship It",
      background_color: "green-600",
      size: "lg"
    )

    assert_response :success
    assert_select "#component-preview button.bg-green-600", text: "Ship It", count: 1
    assert_select "#component-preview button.text-lg", count: 1
    assert_select "#state-inspector", text: /Ship It/
  end

  test "unchecked booleans have an explicit false submission" do
    get story_path("new_dsl_methods", story_variant: "form_controls")

    assert_response :success
    assert_select "input[type='hidden'][name='show_label'][value='0']", count: 1
    assert_select "input[type='checkbox'][name='show_label'][value='1'][checked]", count: 1

    get story_path(
      "new_dsl_methods",
      story_variant: "form_controls",
      selected_color: "blue",
      show_label: "0",
      label_text: "Choose a color:"
    )

    assert_response :success
    assert_select "#component-preview label[for='color-select']", count: 0
    assert_select "#component-preview select[name='color']", count: 1
  end
end
