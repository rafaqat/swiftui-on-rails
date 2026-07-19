# frozen_string_literal: true

require "application_system_test_case"

class HomeCounterTest < ApplicationSystemTestCase
  test "primary counter responds to every rendered action" do
    visit counter_path

    within "[data-counter='true']", text: /Counter:/ do
      assert_selector "[data-counter-label='true']", text: "Counter: 0"

      click_button "+"
      assert_selector "[data-counter-label='true']", text: "Counter: 1"

      click_button "+"
      assert_selector "[data-counter-label='true']", text: "Counter: 2"

      click_button "-"
      assert_selector "[data-counter-label='true']", text: "Counter: 1"

      click_button "Reset"
      assert_selector "[data-counter-label='true']", text: "Counter: 0"
    end

    assert_no_console_errors
  end
end
