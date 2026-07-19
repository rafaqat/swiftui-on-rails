# frozen_string_literal: true

require "test_helper"

module Demos
  class MotionControllerTest < ActionDispatch::IntegrationTest
    test "renders all six motion tiles" do
      get demos_motion_path

      assert_response :success
      assert_select "#motion-count"
      assert_select ".btn-springy", minimum: 4
      assert_select "#motion-reveal .animate-pulse", count: 4
      assert_select "[style*='view-transition-name']", count: 8
      assert_select "meta[name='view-transition']", count: 1
      assert_select ".motion-float-a"
    end

    test "bump replaces the counter with an insertion transition" do
      get demos_motion_path
      post demos_motion_bump_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, 'turbo-stream action="replace" target="motion-count"'
      assert_includes response.body, "motion-enter-scale"
      assert_includes response.body, ">1<"
    end

    test "burst appends three staggered toasts" do
      get demos_motion_path
      post demos_motion_burst_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_equal 3, response.body.scan('turbo-stream action="append" target="toasts"').length
      assert_includes response.body, "motion-enter-move-up"
      assert_includes response.body, "animation-delay: 240ms"
      assert_includes response.body, 'data-motion-exit="motion-exit-opacity"'
    end

    test "shuffle changes the order and redirects for the page morph" do
      get demos_motion_path
      before = Demos::MotionState.new(session[:demos_motion_state]).order

      post demos_motion_shuffle_path
      assert_redirected_to demos_motion_path

      after = Demos::MotionState.new(session[:demos_motion_state]).order
      refute_equal before, after
    end

    test "reveal swaps skeletons for staggered content and back" do
      get demos_motion_path
      post demos_motion_reveal_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, 'turbo-stream action="replace" target="motion-reveal"'
      assert_includes response.body, "motion-enter-move-up"
      assert_includes response.body, "animation-delay: 270ms"

      post demos_motion_reveal_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_includes response.body, "animate-pulse"
    end
  end
end
