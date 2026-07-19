# frozen_string_literal: true

require "test_helper"

class SimpleCounterTest < ViewComponent::TestCase
  def test_simple_counter_renders
    render_inline(SimpleCounterComponent.new(count: 5))
    assert_text "Count: 5"
  end
end
