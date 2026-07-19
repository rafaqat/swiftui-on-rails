# frozen_string_literal: true

require "application_system_test_case"

class SimpleTestPageTest < ApplicationSystemTestCase
  test "Swift UI DSL components render as interactive DOM" do
    visit counter_path

    assert_selector "[data-sui-component='CounterComponent']", count: 4
    assert_selector "[data-counter='true'] [data-counter-display='true']", count: 4
    assert_selector "[data-counter='true'] button[data-sui-actions]", count: 12
    assert_no_selector "[data-controller], [data-action]"

    assert_no_page_errors
    assert_no_console_errors
  end
end
