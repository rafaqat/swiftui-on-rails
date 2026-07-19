# frozen_string_literal: true

require "test_helper"

module Demos
  class PreferencesControllerTest < ActionDispatch::IntegrationTest
    test "renders the reactive preferences panel" do
      get demos_preferences_path

      assert_response :success
      assert_select "[data-sui-root='1'][data-sui-component='PreferencesComponent']"
      assert_select "button[data-sui-actions]"
      assert_select "input#preferences-accent"
      assert_select "button", text: "Moss"
    end
  end
end
