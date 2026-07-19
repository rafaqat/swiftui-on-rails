# frozen_string_literal: true

require "test_helper"

class StateDebugTest < ViewComponent::TestCase
  def test_counter_state_initialization
    component = CounterComponent.new(initial_count: 5)

    render_inline(component)

    assert_selector "[data-sui-root='1'][data-sui-component='CounterComponent']"
    assert_selector "[data-counter-display='true']", text: "5"
    assert_selector "[data-counter-label='true']", text: "Counter: 5"
  end
end
