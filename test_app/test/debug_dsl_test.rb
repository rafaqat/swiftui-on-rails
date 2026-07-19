require "test_helper"

class DebugDslTest < ViewComponent::TestCase
  class TestComponent < ApplicationComponent
    swift_ui do
      div do
        text("Component body")
      end.tw("group").relative
    end
  end

  test "component swift_ui blocks expose chainable DSL elements" do
    render_inline(TestComponent.new)

    assert_selector "div.group.relative", count: 1, text: "Component body"
  end
end
