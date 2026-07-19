# frozen_string_literal: true

require "application_system_test_case"

class ShowcaseOperationsTest < ApplicationSystemTestCase
  test "operator can trigger and recover an incident over the live dashboard" do
    visit showcase_operations_path

    assert_selector "h1", text: "Live operations control room"
    assert_selector "[data-status='ready']", text: "Rails route ready"

    within "[data-service-id='api']" do
      click_button "Trigger incident"
      assert_selector "[data-testid='api-status']", text: "Degraded"
    end
    assert_selector "[data-testid='incident-count']", text: "1"
    assert_text "Latency incident detected"
    within "[data-testid='activity-feed']" do
      assert_text "Latency incident detected"
    end

    within "[data-service-id='api']" do
      click_button "Recover"
      assert_selector "[data-testid='api-status']", text: "Operational"
    end

    assert_no_page_errors
  end
end
