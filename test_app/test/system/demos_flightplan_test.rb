# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: route-backed move buttons drive the authoritative
# endpoint and the Turbo Stream response re-renders the board. Exhaustive move
# semantics live in flightplan_state_test.rb.
class DemosFlightplanTest < ApplicationSystemTestCase
  test "moving a card across columns updates the board" do
    visit_demo("flightplan")

    assert_selector "[data-flightplan-column]", count: 3
    within("[data-flightplan-column='backlog']") do
      assert_selector "[data-flightplan-card-key='orbit-nav']"
    end

    card = find("[data-flightplan-card-key='orbit-nav']")
    # The move controls reveal on hover/focus (opacity-0 → group-hover/
    # focus-within:opacity-100). Headless-Chrome hover is unreliable in CI, so
    # locate the real route-backed submit button regardless of reveal state and
    # activate it directly — this still drives the authoritative PATCH move.
    move_button = card.find("button[aria-label*='next column']", visible: :all)
    page.execute_script("arguments[0].click()", move_button)

    within("[data-flightplan-column='in_flight']") do
      assert_selector "[data-flightplan-card-key='orbit-nav']", wait: 5
    end
    assert_text "4/4"

    assert_demo_healthy
  end
end
