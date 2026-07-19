# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: walking the whole wizard in a browser with server
# validation and the native-dialog success sheet. Validation matrix lives in
# onboard_state_test.rb.
class DemosOnboardTest < ApplicationSystemTestCase
  test "completes the wizard end to end with a validation stumble" do
    visit_demo("onboard")

    # Native HTML5 validation blocks the empty submit before it reaches the
    # server (the server-side path is covered in the controller test).
    click_button "Continue"
    assert_selector "input#onboard-full-name"

    fill_in "full_name", with: "Ada Lovelace"
    choose "Engineer", allow_label_click: true
    click_button "Continue"

    fill_in "team_name", with: "Orbital Systems"
    choose "2-10", allow_label_click: true
    click_button "Continue"

    choose "daily", allow_label_click: true
    click_button "Continue"

    assert_text "Ada Lovelace"
    click_button "Confirm & finish"

    assert_selector "dialog[open]", wait: 5
    assert_text "Welcome aboard, Ada Lovelace!"

    click_button "Start over"
    assert_selector "input#onboard-full-name", wait: 5

    assert_demo_healthy
  end
end
