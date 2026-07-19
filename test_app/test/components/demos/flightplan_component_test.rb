# frozen_string_literal: true

require "test_helper"

module Demos
  class FlightplanComponentTest < ViewComponent::TestCase
    def test_renders_columns_cards_and_wip_badge
      render_inline(FlightplanComponent.new(columns: FlightplanState.new.columns))

      assert_selector "[data-flightplan-board='true']"
      assert_selector "[data-flightplan-column='backlog']"
      assert_selector "[data-flightplan-card-key]", count: FlightplanState::CARDS.length
      assert_text "3/4"
    end

    def test_cards_expose_no_javascript_move_forms
      render_inline(FlightplanComponent.new(columns: FlightplanState.new.columns))

      assert_selector "form[action^='/demos/flightplan/cards/'] button[aria-label^='Move']"
      assert_selector "form[action='/demos/flightplan/reset']"
    end

    def test_edge_columns_omit_impossible_moves
      render_inline(FlightplanComponent.new(columns: FlightplanState.new.columns))

      within_backlog = page.find("[data-flightplan-column='backlog']")
      assert_no_selector "[data-flightplan-column='backlog'] button[aria-label*='previous']"
      assert within_backlog
    end
  end
end
