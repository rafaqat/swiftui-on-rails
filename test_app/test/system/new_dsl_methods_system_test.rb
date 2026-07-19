# frozen_string_literal: true

require "application_system_test_case"

class NewDslMethodsSystemTest < ApplicationSystemTestCase
  test "form controls preserve labels, option values, and selection" do
    visit storybook_show_path(
      story: "new_dsl_methods",
      story_variant: "form_controls",
      selected_color: "green"
    )

    within "#component-preview" do
      assert_selector "label[for='color-select']", text: "Choose a color:"
      assert_selector "select[name='color']"
      assert_selector "option[value='red']", text: "Red", visible: :all
      assert_selector "option[value='green']", text: "Green", visible: :all
      assert_equal "green", find("select[name='color']").value
    end
  end

  test "advanced and inline style modifiers reach the rendered DOM" do
    visit storybook_show_path(
      story: "new_dsl_methods",
      story_variant: "advanced_styling",
      break_mode: "avoid-page",
      group_opacity: 50
    )

    within "#component-preview" do
      assert_selector ".group"
      assert_selector ".group-hover\\:opacity-50"
      assert_selector ".break-inside-avoid-page", count: 4
      assert_selector ".hover\\:ring-2", text: "Hover Me"
    end

    visit storybook_show_path(
      story: "new_dsl_methods",
      story_variant: "flex_and_styles",
      tooltip_text: "Gradient details"
    )

    within "#component-preview" do
      assert_selector ".flex-shrink-0"
      assert_selector "[title='Gradient details']"
      assert_selector "[style*='linear-gradient']"
    end
  end
end
