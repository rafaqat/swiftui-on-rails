# frozen_string_literal: true

require "test_helper"

class AtlasMissionControlComponentTest < ViewComponent::TestCase
  setup do
    @state = Showcase::MissionControlState.new
  end

  test "composes the mission workspace with stable reactive identity and semantic regions" do
    render_inline(component)

    assert_selector "#atlas-mission-control[data-sui-root='1']", count: 1
    assert_selector "[data-swift-ui-theme='dark'] h1.swift-ui-font-large-title.swift-ui-foreground-primary"
    assert_selector "#atlas-composition .swift-ui-text-style-supporting.swift-ui-foreground-secondary"
    assert_selector "#atlas-readiness-summary .swift-ui-text-style-metadata.swift-ui-foreground-tertiary"
    assert_selector "main", count: 0
    assert_selector "nav[aria-label='Atlas command navigation']", count: 1
    assert_selector "#atlas-mission-overview"
    assert_selector "#atlas-systems"
    assert_selector "#atlas-alerts"
    assert_selector "#atlas-documents"
    assert_selector "#atlas-composition", text: "tab_view"
    refute_includes page.native.to_s, "{label:"
    refute_includes page.native.to_s, "#<struct SwiftUIRails::DSL::TabDefinition"
  end

  test "renders production DSL capabilities and real route-backed forms" do
    render_inline(component(surface: :storybook, presentation: "brief"))

    assert_selector "#atlas-command-sheet[open]"
    assert_selector "#atlas-mission-tabs[data-sui-tabs]"
    assert_selector "#atlas-telemetry-chart svg"
    assert_selector "#atlas-orbit-canvas canvas"
    assert_selector "#atlas-ground-map svg"
    assert_selector "#atlas-flight-plan[data-sui-workflow]"
    assert_selector "#atlas-systems [data-sui-workflow]"
    assert_selector "#atlas-flight-plan-import[enctype='multipart/form-data']"
    assert_selector "form[action*='/showcase/mission-control/advance'][method='POST'][data-turbo='true']", visible: :all
    assert_selector "form[action*='/showcase/mission-control/reset'][method='POST'][data-turbo='true']", visible: :all
    assert_selector "input[name='utf8'][value='✓']", minimum: 2, visible: :all
  end

  test "rejects unbounded surface and presentation props" do
    assert_raises(ArgumentError) { component(surface: :admin) }
    assert_raises(ArgumentError) { component(presentation: "arbitrary") }
  end

  private

  def component(surface: :showcase, presentation: nil)
    AtlasMissionControlComponent.new(
      phase: @state.phase,
      sequence_items: @state.sequence_items,
      system_items: @state.system_items,
      alert_items: @state.alert_items,
      telemetry: @state.telemetry,
      activity: @state.activity,
      summary: {
        readiness: @state.readiness,
        hold_count: @state.hold_count,
        escalated_alerts: @state.escalated_alerts,
        mission_status: @state.mission_status
      },
      document: @state.document,
      surface: surface,
      presentation: presentation
    )
  end
end
