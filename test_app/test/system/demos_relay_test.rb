# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: URL-backed thread selection, a send that earns a
# canned reply, and route-backed archiving through Turbo Streams.
class DemosRelayTest < ApplicationSystemTestCase
  test "selecting, sending, and archiving through Rails-owned actions" do
    visit_demo("relay")

    click_link "Launch window moved up"
    assert_current_path(/thread=launch-window/, wait: 5)
    assert_selector "input[name='body']", wait: 5

    fill_in "body", with: "Go for the earlier window."
    click_button "Send"
    assert_text "Go for the earlier window.", wait: 5
    assert_text "Copy that — noted on our end.", wait: 5

    find("#relay-archive-button").click
    assert_no_selector "a[data-relay-thread='launch-window']", wait: 5
    assert_selector "a[data-relay-thread]", count: 2

    assert_demo_healthy
  end
end
