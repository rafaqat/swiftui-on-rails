# frozen_string_literal: true

require "test_helper"

module Demos
  class OnboardControllerTest < ActionDispatch::IntegrationTest
    test "renders step one with the progress indicator" do
      get demos_onboard_path

      assert_response :success
      assert_select "progress"
      assert_select "input#onboard-full-name"
      assert_select "button", text: "Continue"
    end

    test "advancing with valid fields moves to the next step" do
      post demos_onboard_advance_path, params: { step: 1, full_name: "Ada", role: "Engineer" }

      assert_redirected_to demos_onboard_path(step: 2)
      follow_redirect!
      assert_select "input#onboard-team-name"
    end

    test "invalid fields re-render the step with an error" do
      post demos_onboard_advance_path, params: { step: 1, full_name: "", role: "Engineer" }

      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: "Full name is required"
    end

    test "deep linking past validated steps clamps back" do
      get demos_onboard_path(step: 4)

      assert_response :success
      assert_select "input#onboard-full-name"
    end

    test "completing the wizard shows the success sheet and reset restarts" do
      post demos_onboard_advance_path, params: { step: 1, full_name: "Ada", role: "Engineer" }
      post demos_onboard_advance_path, params: { step: 2, team_name: "Orbital", team_size: "2-10" }
      post demos_onboard_advance_path, params: { step: 3, digest: "daily" }
      post demos_onboard_advance_path, params: { step: 4 }
      follow_redirect!

      assert_select "dialog[open]" do
        assert_select "button", text: "Start over"
      end

      post demos_onboard_reset_path
      follow_redirect!
      assert_select "dialog[open]", count: 0
    end
  end
end
