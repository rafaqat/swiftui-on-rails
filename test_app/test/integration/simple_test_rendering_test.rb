# frozen_string_literal: true

require "test_helper"

class SimpleTestRenderingTest < ActionDispatch::IntegrationTest
  test "counter page renders each configured DSL component" do
    get counter_path

    assert_response :success
    assert_select "h1", text: "Counter Component"
    assert_select "[data-sui-component='CounterComponent']", count: 4

    expected_counters = [
      { count: 0, step: 1, label: "Counter" },
      { count: 0, step: 5, label: "Steps" },
      { count: 100, step: 10, label: "Score" },
      { count: 50, step: 1, label: "Items" }
    ]

    expected_counters.each do |counter|
      assert_select "[data-counter-label='true']", text: "#{counter[:label]}: #{counter[:count]}", count: 1
    end

    assert_select "button", text: "+", count: 4
    assert_select "button", text: "Reset", count: 4
    assert_select "button", text: "-", count: 4
  end
end
