# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: an explicit route-backed refresh advances the board,
# and the URL-driven range switcher swaps the window. Telemetry math is
# covered in pulse_telemetry_test.rb.
class DemosPulseTest < ApplicationSystemTestCase
  test "board refreshes and switches ranges through the URL" do
    visit_demo("pulse")

    assert_selector "#pulse-board[data-pulse-tick='0']"

    click_link "Refresh"
    assert_current_path(/tick=1/, wait: 5)
    assert_selector "#pulse-board[data-pulse-tick='1']"
    assert_text(/live · tick 1/i)

    click_link "Last hour"
    assert_current_path(/range=1h/, wait: 5)
    assert_selector "a[aria-current='page']", text: "Last hour"

    assert_demo_healthy
  end
end
