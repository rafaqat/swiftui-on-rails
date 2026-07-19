# frozen_string_literal: true

require "test_helper"

class ReactiveCounterComponentTest < ViewComponent::TestCase
  test "renders declared state binding and encrypted lifecycle metadata" do
    render_inline(ReactiveCounterComponent.new(label: "Samples"))

    root = page.find("[data-sui-root='1']")
    assert_equal "Samples", root.text.match?(/Samples/) ? "Samples" : nil
    assert root["data-sui-snapshot"].present?
    assert root["data-sui-stream"].present?
    assert_selector "input[name='step'][value='1'][data-sui-binding-type='integer']"
    assert_selector "[data-reactive-counter-display]", text: "0"
    assert_selector "button", text: "Increase"
  end

  test "snapshot is bound to component identity and keeps state private" do
    component = ReactiveCounterComponent.new(label: "Private label")
    component.count = 4
    component.step.value = 2
    component_id = "swift-ui-reactive-counter-component-42"
    token = SwiftUIRails::Reactive::ReactiveComponentSnapshot.generate(component, component_id: component_id)

    payload = SwiftUIRails::Reactive::ReactiveComponentSnapshot.verified(
      token,
      component_id: component_id,
      component_class: "ReactiveCounterComponent"
    )

    assert_equal 4, payload.dig("state", "count")
    assert_equal 2, payload.dig("bindings", "step")
    refute_includes token, "Private label"
    assert_nil SwiftUIRails::Reactive::ReactiveComponentSnapshot.verified(
      token,
      component_id: "swift-ui-reactive-counter-component-99",
      component_class: "ReactiveCounterComponent"
    )
    assert_nil SwiftUIRails::Reactive::ReactiveComponentSnapshot.verified(
      "#{token}tampered",
      component_id: component_id,
      component_class: "ReactiveCounterComponent"
    )
  end

  test "state remains typed when assigned or restored" do
    component = ReactiveCounterComponent.new

    assert_raises(TypeError) { component.count = "four" }
    assert_raises(TypeError) { component.state_values = { count: "four" } }
    assert_raises(TypeError) { component.binding_values = { step: "two" } }
    assert_equal 0, component.count
    assert_equal 1, component.step.value
  end
end
