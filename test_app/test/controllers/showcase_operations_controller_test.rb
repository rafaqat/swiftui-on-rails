# frozen_string_literal: true

require "test_helper"

class ShowcaseOperationsControllerTest < ActionDispatch::IntegrationTest
  test "renders the server-owned operations dashboard" do
    get showcase_operations_path

    assert_response :success
    assert_select "main", count: 1
    assert_select "h1", text: "Live operations control room"
    assert_select "[data-controller]", count: 0
    assert_select "[data-status='ready']", text: "Rails route ready"
    assert_select "[data-service-id]", count: 3
    assert_select "[data-service-id] .text-slate-400", minimum: 9
    assert_select "[data-service-id] button.bg-violet-600", count: 3
  end

  test "applies an allowlisted event through a turbo stream" do
    post showcase_operations_events_path,
      params: { event_type: "incident", service_id: "api" },
      headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_includes response.body, 'target="operations-dashboard"'
    assert_includes response.body, "Degraded"
    assert_includes response.body, "Latency incident detected"
  end

  test "persists state for normal html fallback requests" do
    post showcase_operations_events_path,
      params: { event_type: "deploy", service_id: "jobs" }

    assert_redirected_to showcase_operations_path
    follow_redirect!
    assert_response :success
    assert_select "[data-service-id='jobs']", text: /v1\.14\.3/
    assert_select "[data-testid='deployment-count']", text: "15"
  end

  test "rejects client-selected methods and unknown services" do
    post showcase_operations_events_path,
      params: { event_type: "send", service_id: "api" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Invalid operations event" }, response.parsed_body)

    post showcase_operations_events_path,
      params: { event_type: "deploy", service_id: "Object" },
      as: :json

    assert_response :unprocessable_entity
  end
end
