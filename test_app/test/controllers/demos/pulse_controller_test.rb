# frozen_string_literal: true

require "test_helper"

module Demos
  class PulseControllerTest < ActionDispatch::IntegrationTest
    test "renders the board with stat cards, chart, and gauges" do
      get demos_pulse_path

      assert_response :success
      assert_select "#pulse-board"
      assert_select "svg"
      assert_select "progress", count: 4
      assert_select "meter", count: 1
      assert_select "a[aria-current='page']", text: "Last 24 hours"
    end

    test "range switching is URL-driven" do
      get demos_pulse_path(range: "7d")

      assert_response :success
      assert_select "a[aria-current='page']", text: "Last 7 days"
    end

    test "tick returns a Turbo Stream replacing the board with the next tick" do
      get demos_pulse_tick_path(range: "1h", tick: 3),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, 'turbo-stream action="replace" target="pulse-board"'
      assert_includes response.body, "Live · tick 4"
    end

    test "hostile params degrade to defaults" do
      get demos_pulse_path(range: "../../etc", tick: "constantize")

      assert_response :success
      assert_select "a[aria-current='page']", text: "Last 24 hours"
    end
  end
end
