# frozen_string_literal: true

require "application_system_test_case"

class VerifyDslStorySourceTest < ApplicationSystemTestCase
  test "Atlas presents the complete trusted component DSL source" do
    visit story_path(story: "atlas_mission_control", story_variant: "command_center")

    assert_selector "#component-preview[data-sui-story='atlas_mission_control'][data-sui-story-variant='command_center']"
    assert_selector "#state-inspector", text: /server state/i
    assert_selector "h2", text: "DSL Story Source"
    assert_text "atlas_mission_control_component.rb"

    within "[aria-label='Scrollable story source']" do
      assert_text "class AtlasMissionControlComponent"
      assert_text "swift_ui do"
      assert_text "navigation_stack"
      assert_text "tab_view"
      assert_text "chart"
      assert_text "canvas"
      assert_text "map"
      assert_text "reorderable_collection"
      assert_text "swipe_actions"
      assert_text "document_workflow"
    end
  end

  test "product layout presents source from its registered story file" do
    visit storybook_show_path(story: "product_layout_simple")

    assert_selector "h2", text: "DSL Story Source"
    assert_text "product_layout_simple_stories.rb"

    within "[aria-label='Scrollable story source']" do
      assert_text "def default"
      assert_text "products = ["
      assert_text "swift_ui do"
      assert_text "grid(columns: 2, spacing: 6)"
      assert_text "dsl_product_card("
      assert_no_text "class ProductLayoutComponent < ApplicationComponent"
    end
  end

  test "button story presents the selected variant source" do
    visit storybook_show_path(story: "dsl_button", story_variant: "default")

    assert_selector "h2", text: "DSL Story Source"
    assert_text "dsl_button_stories.rb"

    within "[aria-label='Scrollable story source']" do
      assert_text "def default("
      assert_text "swift_ui do"
      assert_text "button(text)"
    end

    assert_selector "#component-preview", text: "Click Me"
    assert_selector "#state-inspector", text: "prop_text"
    assert_no_selector "[data-controller], [data-action]"
  end
end
