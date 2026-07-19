# frozen_string_literal: true

require "test_helper"

module Demos
  class MotionStateTest < ActiveSupport::TestCase
    test "starts at zero with cards in order and skeletons showing" do
      state = MotionState.new

      assert_equal 0, state.count
      assert_equal (1..8).to_a, state.order
      assert_not state.revealed?
    end

    test "bump increments and clamps" do
      state = MotionState.new("count" => 9998)
      state.bump!
      state.bump!

      assert_equal 9999, state.count
    end

    test "shuffle always changes the order" do
      state = MotionState.new
      10.times do
        before = state.order.dup
        state.shuffle!
        refute_equal before, state.order
      end
      assert_equal (1..8).to_a, state.order.sort
    end

    test "reveal toggles" do
      state = MotionState.new
      assert state.toggle_reveal!.revealed?
      assert_not state.toggle_reveal!.revealed?
    end

    test "tampered session data falls back to defaults" do
      state = MotionState.new("count" => "constantize", "order" => [ 1, 1, 2 ], "revealed" => "yes")

      assert_equal 0, state.count
      assert_equal (1..8).to_a, state.order
      assert_not state.revealed?
    end

    test "round-trips through session serialization" do
      state = MotionState.new
      state.bump!
      state.shuffle!
      state.toggle_reveal!

      restored = MotionState.new(state.to_h)
      assert_equal state.to_h, restored.to_h
    end
  end
end
