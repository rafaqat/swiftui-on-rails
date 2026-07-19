# frozen_string_literal: true

require "test_helper"

class PreferencesComponentTest < ViewComponent::TestCase
  def test_renders_reactive_container_with_controls_and_preview
    render_inline(PreferencesComponent.new)

    assert_selector "[data-sui-root='1'][data-sui-component='PreferencesComponent']"
    assert_selector "button", text: "Aurora"
    assert_selector "[data-preferences-density]", text: "Comfortable"
    assert_selector "input#preferences-accent[type='range']"
    assert_text "Orbit Dashboard"
    assert_selector ".from-sky-500"
  end

  def test_state_drives_the_preview_styling
    component = PreferencesComponent.new
    component.theme = "ember"
    component.density = 3
    component.show_badges = false

    render_inline(component)

    assert_selector ".from-amber-400"
    assert_selector ".p-10"
    assert_no_selector "[data-preferences-theme-badge]"
  end

  def test_density_stays_within_bounds_semantics
    component = PreferencesComponent.new
    component.density = 1

    render_inline(component)

    assert_selector "[data-preferences-density]", text: "Compact"
    assert_selector "button[aria-label='Decrease density']"
  end
end
