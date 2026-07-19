# frozen_string_literal: true

require "application_system_test_case"

class ShowcaseMissionControlTest < ApplicationSystemTestCase
  test "complex surface composes advanced content presentations local state and tabs" do
    visit showcase_mission_control_path

    assert_selector "#atlas-mission-control[data-sui-root='1']"
    assert_selector "h1", text: "Orbital launch command"
    assert_selector "#atlas-command-toolbar[data-sui-toolbar][data-sui-enhanced='toolbar']"
    assert_selector "#atlas-telemetry-chart"
    assert_selector "#atlas-orbit-canvas canvas"
    assert_selector "#atlas-ground-map"
    assert_selector "#atlas-mission-tabs [role='tablist']"
    assert_no_selector "#atlas-mission-control", text: "#<struct SwiftUIRails::DSL::"

    click_link "Mission brief"
    assert_selector "dialog#atlas-command-sheet[open][role='dialog']"
    assert_text "Atlas flight rule 4.2"
    find("dialog#atlas-command-sheet").send_keys(:escape)
    assert_no_selector "dialog#atlas-command-sheet[open]"
    assert_equal "Mission brief", page.evaluate_script("document.activeElement.textContent.trim()")

    initial_token = reactive_snapshot_token
    precision_control = find("#atlas-precision-control", text: "Precision off")
    page.execute_script("arguments[0].focus()", precision_control)
    assert_equal "atlas-precision-control", page.evaluate_script("document.activeElement.id")
    precision_control.click
    assert_selector "#atlas-precision-control[aria-pressed='true']", text: "Precision on"
    assert_equal "atlas-precision-control", page.evaluate_script("document.activeElement.id")
    precision_token = reactive_snapshot_token
    refute_equal initial_token, precision_token

    click_button "Precision on"
    assert_selector "#atlas-precision-control[aria-pressed='false']", text: "Precision off"
    refute_equal precision_token, reactive_snapshot_token

    click_link "Launch sequence"
    assert_selector "#atlas-mission-tabs-tab-sequence[aria-selected='true']"
    assert_selector "#atlas-mission-tabs-panel-telemetry[hidden]", visible: :all
    assert_selector "#atlas-flight-plan [role='listitem']", count: 5

    click_link "Flight documents"
    assert_selector "#atlas-mission-tabs-tab-documents[aria-selected='true']"
    assert_selector "#atlas-mission-tabs-panel-sequence[hidden]", visible: :all
    assert_selector "#atlas-flight-plan-import"

    assert_no_page_errors
    assert_no_console_errors
  end

  test "server workflows persist order enforce interlocks advance the count and verify documents" do
    visit showcase_mission_control_path

    assert_equal %w[weather payload propellant guidance range], sequence_keys
    assert_selector "#atlas-mission-status", text: "HOLD"
    assert_phase "T−12", "Terminal count setup"

    open_count_controls
    blocked_advance_form = find("#atlas-count-controls form")
    page.execute_script("arguments[0].setAttribute('data-turbo', 'false')", blocked_advance_form)
    click_button "Advance count"
    assert_text "Resolve every system hold before advancing the count."
    assert_phase "T−12", "Terminal count setup"

    click_link "Launch sequence"
    within "#atlas-flight-plan" do
      click_button "Move down", match: :first
    end
    assert_text "Launch sequence updated."
    assert_equal %w[payload weather propellant guidance range], sequence_keys

    refresh
    assert_equal %w[payload weather propellant guidance range], sequence_keys
    assert_phase "T−12", "Terminal count setup"

    click_link "Launch sequence"
    reveal_swipe_actions("#atlas-systems .swift-ui-swipe-actions[aria-label='Range safety system']")
    range_row = find("#atlas-systems .swift-ui-swipe-actions[aria-label='Range safety system']")
    assert_selector "#atlas-systems .swift-ui-swipe-actions[aria-label='Range safety system'] [role='status']",
      text: "HOLD"
    range_form = range_row.find("form", text: "Set GO")
    page.execute_script("arguments[0].setAttribute('data-turbo', 'false')", range_form)
    range_form.find_button("Set GO").click
    assert_text "System readiness updated."
    assert_selector "#atlas-mission-status", text: "GO"

    open_count_controls
    click_button "Advance count"
    assert_text "The launch count advanced."
    assert_phase "T−04", "Autosequence"

    refresh
    assert_equal %w[payload weather propellant guidance range], sequence_keys
    assert_phase "T−04", "Autosequence"
    assert_selector "#atlas-mission-status", text: "GO"

    click_link "Flight documents"
    within "#atlas-documents" do
      attach_file(
        "Flight rule or PDF package (up to 1 MB)",
        Rails.root.join("test/fixtures/files/workflow-demo.txt")
      )
      assert_text "1 file selected"
      click_button "Verify package"
    end
    assert_selector "#atlas-document-status", text: "workflow-demo.txt · import", visible: :all

    refresh
    assert_selector "#atlas-document-status", text: "workflow-demo.txt · import", visible: :all
    assert_equal %w[payload weather propellant guidance range], sequence_keys
    assert_phase "T−04", "Autosequence"

    assert_no_page_errors
    assert_no_console_errors
  end

  test "storybook command center renders the complex variant and complete DSL source" do
    visit story_path(story: "atlas_mission_control", story_variant: "command_center")

    within "#component-preview" do
      assert_selector "#atlas-mission-control"
      assert_selector "#atlas-telemetry-chart"
      assert_selector "#atlas-flight-plan", visible: :all
      assert_selector "#atlas-documents", visible: :all
    end
    assert_selector "h2", text: "DSL Story Source"
    assert_text "atlas_mission_control_component.rb"
    assert_text "class AtlasMissionControlComponent"
    assert_text "swift_ui do"

    assert_no_page_errors
    assert_no_console_errors
  end

  private

  def reactive_snapshot_token
    find("#atlas-mission-control")["data-sui-snapshot"]
  end

  def sequence_keys
    all(
      "#atlas-flight-plan [role='listitem']",
      visible: :all,
      count: Showcase::MissionControlState::SEQUENCE.length
    ).map { |item| item["data-sui-workflow-key"] }
  end

  def assert_phase(code, name)
    assert_selector "[aria-label='Current mission phase']", text: code
    assert_selector "[aria-label='Current mission phase']", text: name
  end

  def open_count_controls
    find("#atlas-count-controls summary", text: "Count controls").click
    assert_selector "#atlas-count-controls[open]"
  end

  def reveal_swipe_actions(selector)
    row = find(selector)
    page.execute_script(<<~JS, row)
      const row = arguments[0]
      row.dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true, pointerId: 72, clientX: 180, clientY: 20
      }))
      row.dispatchEvent(new PointerEvent("pointerup", {
        bubbles: true, pointerId: 72, clientX: 40, clientY: 22
      }))
    JS
    assert_selector "#{selector}[data-sui-swipe-state='revealed']"
  end
end
