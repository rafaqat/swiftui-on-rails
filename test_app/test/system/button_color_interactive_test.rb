# frozen_string_literal: true

require "application_system_test_case"

class ButtonColorInteractiveTest < ApplicationSystemTestCase
  test "button colors update through one explicit Rails transition" do
    visit storybook_show_path(story: "dsl_button")

    assert_selector "#component-preview button.bg-blue-600.text-white", text: "Click Me"

    find("#storybook-control-background_color option[value='purple-600']").select_option
    find("#storybook-control-text_color option[value='purple-900']").select_option
    click_button "Apply controls"

    assert_selector "#component-preview button.bg-purple-600.text-purple-900", text: "Click Me", wait: 10
    assert_selector "select[name='background_color'] option[value='purple-600']:checked"
    assert_selector "select[name='text_color'] option[value='purple-900']:checked"

    within "#state-inspector" do
      assert_text "prop_background_color"
      assert_text "purple-600"
      assert_text "prop_text_color"
      assert_text "purple-900"
    end

    within "[aria-label='Scrollable story source']" do
      assert_text "background_color: \"blue-600\""
      assert_text ".bg(background_color)"
    end

    query = URI.decode_www_form(URI.parse(page.current_url).query).to_h
    assert_equal "purple-600", query.fetch("background_color")
    assert_equal "purple-900", query.fetch("text_color")
  end
end
