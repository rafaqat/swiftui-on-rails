# frozen_string_literal: true

require "application_system_test_case"

class CounterSemanticActionsTest < ApplicationSystemTestCase
  test "declared Ruby actions update the server-owned counter" do
    visit story_path(story: "counter_component")

    within "#component-preview [data-counter]" do
      assert_selector "[data-counter-display]", text: "0"
      assert_text "Counter: 0"

      click_button "+"
      click_button "+"
      assert_selector "[data-counter-display]", text: "2", wait: 10
      assert_text "Counter: 2"

      click_button "-"
      click_button "Reset"
      assert_selector "[data-counter-display]", text: "0", wait: 10
      assert_text "Counter: 0"
    end
  end

  test "explicit GET controls configure the next server render" do
    visit story_path(story: "counter_component")

    fill_in "initial_count", with: "10"
    fill_in "step", with: "5"
    fill_in "label", with: "Orders"
    click_button "Apply controls"

    assert_selector "#component-preview [data-counter-display]", text: "10", wait: 10
    assert_selector "#component-preview", text: "Orders: 10"

    within "#component-preview [data-counter]" do
      click_button "+"
      assert_selector "[data-counter-display]", text: "15", wait: 10
      assert_text "Orders: 15"
    end
  end
end
