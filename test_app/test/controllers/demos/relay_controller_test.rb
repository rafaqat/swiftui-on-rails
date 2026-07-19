# frozen_string_literal: true

require "test_helper"

module Demos
  class RelayControllerTest < ActionDispatch::IntegrationTest
    test "renders the route-backed inbox" do
      get demos_relay_path

      assert_response :success
      assert_select "#relay-app"
      assert_select "#relay-app[data-controller]", count: 0
      assert_select "a[data-relay-thread]", count: 3
    end

    test "selecting a thread through the URL marks it read and shows the composer" do
      get demos_relay_path(thread: "launch-window")

      assert_response :success
      assert_select "input[name='body']"
      assert_select "button#relay-archive-button"

      get demos_relay_path
      launch_row = css_select("a[data-relay-thread='launch-window'] span").first
      assert launch_row
    end

    test "sending a message returns a Turbo Stream with the reply and a toast" do
      get demos_relay_path(thread: "fuel-report")
      post demos_relay_send_path, params: { thread: "fuel-report", body: "On it." },
                                  headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, 'turbo-stream action="replace" target="relay-app"'
      assert_includes response.body, "On it."
      assert_includes response.body, 'turbo-stream action="append" target="toasts"'
    end

    test "empty sends are rejected with the authoritative shell" do
      get demos_relay_path(thread: "fuel-report")
      post demos_relay_send_path, params: { thread: "fuel-report", body: "  " },
                                  headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :unprocessable_entity
    end

    test "archiving removes the thread and archiving everything reaches inbox zero" do
      get demos_relay_path
      Demos::RelayState::THREADS.each do |thread|
        patch demos_relay_archive_path, params: { thread: thread[:id] },
                                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success
      end

      get demos_relay_path
      assert_select "a[data-relay-thread]", count: 0
      assert_select "button", text: "Restore inbox"

      post demos_relay_reset_path
      follow_redirect!
      assert_select "a[data-relay-thread]", count: 3
    end
  end
end
