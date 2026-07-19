# frozen_string_literal: true

require "application_system_test_case"

class SimpleCounterTest < ApplicationSystemTestCase
  test "configured step counter applies its own step and reset values" do
    visit counter_path

    within "[data-counter='true']", text: /Steps:/ do
      assert_selector "[data-counter-label='true']", text: "Steps: 0"

      click_button "+"
      assert_selector "[data-counter-label='true']", text: "Steps: 5"

      click_button "+"
      assert_selector "[data-counter-label='true']", text: "Steps: 10"

      click_button "Reset"
      assert_selector "[data-counter-label='true']", text: "Steps: 0"
    end
  end
end
