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
    card.hover
    card.find("button[aria-label*='next column']").click

    within("[data-flightplan-column='in_flight']") do
      assert_selector "[data-flightplan-card-key='orbit-nav']", wait: 5
    end
    assert_text "4/4"

    assert_demo_healthy
  end
end
