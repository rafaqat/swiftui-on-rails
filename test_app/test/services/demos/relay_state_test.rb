# frozen_string_literal: true

require "test_helper"

module Demos
  class RelayStateTest < ActiveSupport::TestCase
    test "starts with all threads unread in the inbox" do
      state = RelayState.new

      assert_equal 3, state.inbox_threads.length
      assert state.inbox_threads.all? { |thread| thread[:unread] }
    end

    test "reading and archiving update the inbox" do
      state = RelayState.new
      state.mark_read!("launch-window")
      refute state.inbox_threads.find { |thread| thread[:id] == "launch-window" }[:unread]

      state.archive!("launch-window")
      assert_equal 2, state.inbox_threads.length
      assert_equal 1, state.archived_count
      assert_nil state.find_thread("launch-window")
    end

    test "sending appends the message and a canned reply" do
      state = RelayState.new
      reply = state.send_message!("fuel-report", "Thanks — reviewing now.")

      messages = state.messages_for("fuel-report")
      assert_equal "Thanks — reviewing now.", messages[-2][:body]
      assert_equal reply, messages[-1][:body]
      assert_equal "Propulsion", messages[-1][:from]
    end

    test "sends validate thread, body, and bounds" do
      state = RelayState.new

      assert_raises(ArgumentError) { state.send_message!("nope", "hi") }
      assert_raises(ArgumentError) { state.send_message!("fuel-report", "   ") }

      long = state.send_message!("fuel-report", "x" * 500)
      assert long
      assert_equal 280, state.messages_for("fuel-report")[-2][:body].length
    end

    test "tampered session data is discarded" do
      state = RelayState.new(
        "read" => ["launch-window", "bogus"],
        "archived" => ["nope"],
        "sent" => { "evil" => [{ "body" => "x" }], "fuel-report" => [{ "from" => "You", "body" => "kept" }] }
      )

      assert_equal 0, state.archived_count
      assert_equal ["kept"], state.messages_for("fuel-report").last(1).map { |message| message[:body] }
    end

    test "round-trips through session serialization" do
      state = RelayState.new
      state.send_message!("fuel-report", "Ping")
      state.archive!("crew-rotation")

      restored = RelayState.new(state.to_h)
      assert_equal state.to_h, restored.to_h
    end

    test "reset restores everything" do
      state = RelayState.new
      state.archive!("crew-rotation")
      state.reset!

      assert_equal 3, state.inbox_threads.length
    end
  end
end
