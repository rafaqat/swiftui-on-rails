# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AtlasMissionControlActionTest < ActionDispatch::IntegrationTest
  test "direct showcase gesture restores typed props and renders nested snapshot data" do
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      get showcase_mission_control_path

      assert_response :success
      document = Nokogiri::HTML(response.body)
      root = document.at_css("#atlas-mission-control[data-sui-root='1']")
      precision = document.at_css("#atlas-precision-control")
      action_id = JSON.parse(
        precision["data-sui-actions"]
      ).fetch("click")

      assert root
      assert action_id

      post_action(root, action_id)

      assert_response :success
      rendered = Nokogiri::HTML.fragment(response.parsed_body.fetch("html"))
      assert_equal "Precision on", rendered.at_css("#atlas-precision-control")&.text&.strip
      assert_equal "Orbital launch command", rendered.at_css("h1")&.text&.strip
      assert_includes rendered.text, "Launch complex 39A"
    end
  end

  test "storybook local gesture state survives consecutive server round trips" do
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      get story_path(story: "atlas_mission_control", variant: "command_center")

      assert_response :success
      document = Nokogiri::HTML(response.body)
      root = document.at_css("#atlas-mission-control[data-sui-root='1']")
      precision = document.at_css("#atlas-precision-control")
      action_id = JSON.parse(
        precision["data-sui-actions"]
      ).fetch("click")
      story_stage = document.at_css("#component-preview[data-sui-story-session]")
      session_id = story_stage && story_stage["data-sui-story-session"]

      assert root
      assert action_id
      assert session_id

      post_action(
        root,
        action_id,
        story_session_id: session_id,
        story_name: "atlas_mission_control",
        story_variant: "command_center"
      )
      assert_response :success
      assert_includes response.parsed_body.fetch("html"), "Precision on"
      assert_equal true, persisted_story_state(session_id).fetch("precision_tracking")

      post_action(
        root,
        action_id,
        story_session_id: session_id,
        story_name: "atlas_mission_control",
        story_variant: "command_center"
      )
      assert_response :success
      assert_includes response.parsed_body.fetch("html"), "Precision off"
      assert_equal false, persisted_story_state(session_id).fetch("precision_tracking")
    end
  end

  private

  def post_action(root, action_id, **context)
    post swift_ui_actions_path,
      params: {
        action_id: action_id,
        component_id: root["id"],
        component_class: "AtlasMissionControlComponent",
        snapshot_token: root["data-sui-snapshot"],
        stream_token: root["data-sui-stream"],
        event_type: "click"
      }.merge(context),
      as: :json,
      headers: { "X-Requested-With" => "XMLHttpRequest" }
  end

  def persisted_story_state(session_id)
    StorySession.find("atlas_mission_control", "command_center", session_id).state
  end
end
