# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class EventHandlersIntegrationTest < ActionDispatch::IntegrationTest
  test "server actions retain encrypted state and stable DOM identity" do
    html = ApplicationController.render(ReactiveCounterComponent.new, layout: false)
    document = Nokogiri::HTML.fragment(html)
    root = document.at_css("[data-sui-root='1']")
    counter_value = document.at_css("[data-reactive-counter-display='true']")
    increase = document.css("button").find { |button| button.text.include?("Increase") }
    action_id = JSON.parse(increase["data-sui-actions"]).fetch("click")

    post swift_ui_actions_path,
      params: {
        action_id: action_id,
        component_id: root["id"],
        component_class: "ReactiveCounterComponent",
        snapshot_token: root["data-sui-snapshot"],
        stream_token: root["data-sui-stream"],
        event_type: "click"
      },
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_includes response.body, %(target="#{root['id']}")
    assert_includes response.body, %(id="#{root['id']}")

    updated_document = Nokogiri::HTML.fragment(response.body)
    updated_counter_value = updated_document.at_css("[data-reactive-counter-display='true']")
    assert_equal "1", updated_counter_value.text
    assert_equal counter_value[SwiftUIRails::RenderIR::PatchLocator::ATTRIBUTE],
      updated_counter_value[SwiftUIRails::RenderIR::PatchLocator::ATTRIBUTE]
  end

  test "counter page renders its server-owned semantic event handlers" do
    get counter_path

    assert_response :success
    assert_select "[data-sui-root='1'][data-sui-component='CounterComponent']", count: 4
    assert_select "button[data-sui-actions]", count: 12
    assert_select "[data-controller], [data-action]", count: 0
  end

  test "swift UI actions endpoint dispatches a registered component action" do
    component = CounterComponent.new
    handled_event = nil
    component.register_component_action("test_action", lambda { |event| handled_event = event })
    html = ApplicationController.render(component, layout: false)
    root = Nokogiri::HTML.fragment(html).at_css("[data-sui-root='1']")

    CounterComponent.stub(:new, ->(**_props) { component }) do
      post swift_ui_actions_path,
        params: {
          action_id: "test_action",
          component_id: root["id"],
          component_class: "CounterComponent",
          snapshot_token: root["data-sui-snapshot"],
          stream_token: root["data-sui-stream"],
          event_type: "click"
        },
        as: :json,
        headers: { "X-Requested-With" => "XMLHttpRequest" }
    end

    assert_response :success
    assert_equal "test_action", handled_event.action_id
    assert_equal "click", handled_event.event_type

    json_response = response.parsed_body
    assert_equal true, json_response["success"]
    assert_equal root["id"], json_response["component_id"]
    assert json_response["snapshot_token"].present?
    refute json_response.key?("state")
  end
end
