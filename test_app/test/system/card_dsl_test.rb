# frozen_string_literal: true

require "application_system_test_case"

class CardDslTest < ApplicationSystemTestCase
  test "card story renders submitted composition without application JavaScript metadata" do
    visit story_path(
      story: "dsl_card",
      card_title: "Release Notes",
      card_content: "A composed card rendered by the Swift UI DSL"
    )

    within "#component-preview" do
      assert_selector ".rounded-lg.shadow-md"
      assert_text "Release Notes"
      assert_text "A composed card rendered by the Swift UI DSL"
      assert_selector "button", text: "Learn More"
      assert_selector "button", text: "Dismiss"
      assert_no_selector "[data-controller], [data-action], [data-live-story-target]"
    end

    assert_no_page_errors
  end
end
