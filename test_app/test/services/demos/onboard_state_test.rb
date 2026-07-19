# frozen_string_literal: true

require "test_helper"

module Demos
  class OnboardStateTest < ActiveSupport::TestCase
    test "starts empty on step one" do
      state = OnboardState.new

      assert_equal 1, state.furthest_step
      assert_not state.completed?
    end

    test "deep links clamp to the furthest validated step" do
      state = OnboardState.new

      assert_equal 1, state.clamp_step(4)
      assert_equal 1, state.clamp_step("constantize")

      state.apply_step!(1, full_name: "Ada", role: "Engineer")
      assert_equal 2, state.clamp_step(4)
    end

    test "steps validate their fields" do
      state = OnboardState.new

      assert_equal "Full name is required", state.apply_step!(1, full_name: "", role: "Engineer")
      assert_equal "Pick a role", state.apply_step!(1, full_name: "Ada", role: "Wizard")
      assert_nil state.apply_step!(1, full_name: "Ada", role: "Engineer")
    end

    test "completing review marks the wizard done" do
      state = OnboardState.new
      state.apply_step!(1, full_name: "Ada", role: "Engineer")
      state.apply_step!(2, team_name: "Orbital", team_size: "2-10")
      state.apply_step!(3, digest: "daily")
      assert_not state.completed?

      state.apply_step!(4, {})
      assert state.completed?
    end

    test "tampered session values are discarded" do
      state = OnboardState.new(
        "full_name" => "x" * 500,
        "role" => "<script>",
        "team_size" => "9000",
        "digest" => "hourly",
        "completed" => "yes"
      )

      assert_equal 80, state.values["full_name"].length
      assert_equal "", state.values["role"]
      assert_equal "", state.values["team_size"]
      assert_equal "weekly", state.values["digest"]
      assert_not state.completed?
    end

    test "reset clears everything" do
      state = OnboardState.new
      state.apply_step!(1, full_name: "Ada", role: "Engineer")
      state.reset!

      assert_equal 1, state.furthest_step
      assert_equal "", state.values["full_name"]
    end
  end
end
