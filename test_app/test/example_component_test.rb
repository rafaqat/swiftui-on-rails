require "test_helper"

class ExampleComponentTest < ViewComponent::TestCase
  class BooleanStateComponent < ApplicationComponent
    state :enabled, true, type: :boolean
  end

  class StateSiblingComponent < ApplicationComponent
  end

  test "renders typed state and semantic Ruby actions" do
    component = ExampleComponent.new
    render_inline(component)

    assert_selector "div.bg-white.rounded-lg.shadow-md.p-6", count: 1
    assert_text "Hello from SwiftUI Rails!"
    assert_text "Count: 0"
    assert_selector "button[data-sui-actions]", text: "+"
    assert_selector "button[data-sui-actions]", text: "Show Details"
    assert_equal %i[counter show_details], component.class.state_definitions.keys
  end

  test "renders a custom title without showing collapsed details" do
    render_inline(ExampleComponent.new(
      title: "Custom Title",
      description: "Hidden details"
    ))

    assert_text "Custom Title"
    refute_text "Hidden details"
  end

  test "state definitions are isolated and preserve false values" do
    component = BooleanStateComponent.new
    component.enabled = false

    assert_equal false, component.enabled
    assert_includes BooleanStateComponent.state_definitions, :enabled
    refute_includes StateSiblingComponent.state_definitions, :enabled
    refute_includes ApplicationComponent.state_definitions, :enabled
  end

  test "snapshot restoration accepts only declared typed state" do
    component = BooleanStateComponent.new
    component.state_values = { "enabled" => false, "story_session_id" => "hijacked" }

    assert_equal false, component.enabled
    assert_equal({ enabled: false }, component.state_values)
    assert_raises(TypeError) { component.enabled = "false" }
  end
end
