# frozen_string_literal: true

require "test_helper"

module Demos
  class FlightplanStateTest < ActiveSupport::TestCase
    test "starts from the default board" do
      state = FlightplanState.new

      assert_equal FlightplanState::DEFAULT_ORDER, state.to_h
      assert_equal %w[backlog in_flight landed], state.columns.map { |column| column[:id] }
    end

    test "moves a card between columns at a position" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "landed", position: 0)

      assert_equal %w[orbit-nav weather-hold payload-seal], state.to_h.fetch("landed")
      refute_includes state.to_h.fetch("backlog"), "orbit-nav"
    end

    test "appends when position is missing and clamps out-of-range positions" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "landed")
      assert_equal "orbit-nav", state.to_h.fetch("landed").last

      state.move!(card: "fuel-audit", to: "landed", position: "999")
      assert_equal "fuel-audit", state.to_h.fetch("landed").last
    end

    test "reordering within a column works" do
      state = FlightplanState.new
      state.move!(card: "telemetry-cal", to: "backlog", position: 0)

      assert_equal "telemetry-cal", state.to_h.fetch("backlog").first
    end

    test "enforces the in-flight WIP limit" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "in_flight")

      error = assert_raises(FlightplanState::WipLimitError) do
        state.move!(card: "fuel-audit", to: "in_flight")
      end
      assert_match(/limit of 4/, error.message)
    end

    test "the WIP limit does not block reordering within the full column" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "in_flight")

      state.move!(card: "orbit-nav", to: "in_flight", position: 0)
      assert_equal "orbit-nav", state.to_h.fetch("in_flight").first
    end

    test "rejects unknown cards, columns, and malformed positions" do
      state = FlightplanState.new

      assert_raises(ArgumentError) { state.move!(card: "nope", to: "landed") }
      assert_raises(ArgumentError) { state.move!(card: "orbit-nav", to: "trash") }
      assert_raises(ArgumentError) { state.move!(card: "orbit-nav", to: "landed", position: "DROP TABLE") }
    end

    test "tampered session data falls back to the default board" do
      missing_cards = { "backlog" => %w[orbit-nav], "in_flight" => [], "landed" => [] }
      assert_equal FlightplanState::DEFAULT_ORDER, FlightplanState.new(missing_cards).to_h

      assert_equal FlightplanState::DEFAULT_ORDER, FlightplanState.new("garbage").to_h
      assert_equal FlightplanState::DEFAULT_ORDER, FlightplanState.new(nil).to_h
    end

    test "round-trips through session serialization" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "landed")

      restored = FlightplanState.new(state.to_h)
      assert_equal state.to_h, restored.to_h
    end

    test "reset restores the default order" do
      state = FlightplanState.new
      state.move!(card: "orbit-nav", to: "landed")
      state.reset!

      assert_equal FlightplanState::DEFAULT_ORDER, state.to_h
    end
  end
end
