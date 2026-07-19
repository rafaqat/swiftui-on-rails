# frozen_string_literal: true

require "test_helper"

module Demos
  class FlightplanControllerTest < ActionDispatch::IntegrationTest
    test "renders the board with three columns" do
      get demos_flightplan_path

      assert_response :success
      assert_select "#flightplan-board"
      assert_select "[data-flightplan-column]", count: 3
      assert_select "[data-flightplan-card-key]", count: FlightplanState::CARDS.length
    end

    test "moves a card via Turbo Stream and persists across requests" do
      get demos_flightplan_path

      patch demos_flightplan_card_move_path(card: "orbit-nav"),
            params: { to: "landed", position: 0 },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, 'turbo-stream action="replace" target="flightplan-board"'

      get demos_flightplan_path
      assert_equal "orbit-nav", Demos::FlightplanState.new(session[:demos_flightplan_state]).to_h.fetch("landed").first
    end

    test "WIP violations return unprocessable with the authoritative board" do
      get demos_flightplan_path
      patch demos_flightplan_card_move_path(card: "orbit-nav"),
            params: { to: "in_flight" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      patch demos_flightplan_card_move_path(card: "fuel-audit"),
            params: { to: "in_flight" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :unprocessable_entity
      assert_includes response.body, "flightplan-board"
      refute_includes Demos::FlightplanState.new(session[:demos_flightplan_state]).to_h.fetch("in_flight"), "fuel-audit"
    end

    test "invalid cards are rejected at the router" do
      patch "/demos/flightplan/cards/..%2Fetc/move", params: { to: "landed" }

      assert_response :not_found
    rescue ActionController::RoutingError
      assert true
    end

    test "html moves redirect back to the board" do
      get demos_flightplan_path
      patch demos_flightplan_card_move_path(card: "orbit-nav"), params: { to: "landed" }

      assert_redirected_to demos_flightplan_path
    end

    test "reset restores the default order" do
      get demos_flightplan_path
      patch demos_flightplan_card_move_path(card: "orbit-nav"), params: { to: "landed" }
      post demos_flightplan_reset_path

      assert_equal FlightplanState::DEFAULT_ORDER,
                   Demos::FlightplanState.new(session[:demos_flightplan_state]).to_h
    end
  end
end
