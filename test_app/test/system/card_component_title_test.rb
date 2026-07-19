# frozen_string_literal: true

require "application_system_test_case"

class CardComponentTitleTest < ApplicationSystemTestCase
  test "card controls update preview and inspector through Rails" do
    visit storybook_show_path(story: "dsl_card")

    assert_selector "#component-preview", text: "DSL Card - Composition Pattern"
    assert_selector "#component-preview .text-lg.font-semibold", text: "Card Title"

    fill_in "storybook-control-card_title", with: "Production Ready Card"
    fill_in "storybook-control-card_content", with: "Server-rendered card content"
    find("#storybook-control-background option[value='blue-50']").select_option
    find("#storybook-control-border_color option[value='purple-200']").select_option
    click_button "Apply controls"

    assert_selector "#component-preview .text-lg.font-semibold", text: "Production Ready Card", wait: 10
    assert_selector "#component-preview", text: "Server-rendered card content", wait: 10
    assert_selector "#component-preview .rounded-lg.bg-blue-50.border-purple-200", wait: 10

    within "#state-inspector" do
      assert_text "prop_card_title"
      assert_text "Production Ready Card"
      assert_text "prop_card_content"
      assert_text "Server-rendered card content"
      assert_text "blue-50"
      assert_text "purple-200"
    end

    within "[aria-label='Scrollable story source']" do
      assert_text "def default("
      assert_text "card_header do"
      assert_text ".bg(background)"
    end

    assert_no_selector "[data-controller], [data-action]"
  end
end
