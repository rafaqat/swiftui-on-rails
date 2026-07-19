# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ShowcaseOperationsChannelTest < ActionCable::Channel::TestCase
  tests ShowcaseOperationsChannel

  setup do
    @component_id = "swift-ui-operations-dashboard-123456789"
    @stream_token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(@component_id)
  end

  test "subscribes a valid dashboard capability to its read-only stream" do
    subscribe component_id: @component_id, stream_token: @stream_token

    assert subscription.confirmed?
    assert_equal 1, subscription.streams.size
    refute_includes ShowcaseOperationsChannel.action_methods, "request_update"
  end

  test "rejects a missing or forged capability" do
    [nil, "forged-#{@stream_token}"].each do |stream_token|
      subscribe component_id: @component_id, stream_token: stream_token

      assert subscription.rejected?
      assert_no_streams
    end
  end

  test "rejects a capability for a different dashboard" do
    other_id = "swift-ui-operations-dashboard-987654321"
    other_token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(other_id)

    subscribe component_id: @component_id, stream_token: other_token

    assert subscription.rejected?
    assert_no_streams
  end

  test "rejects a capability issued for a different authorization context" do
    token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(
      @component_id,
      authorization_context: "session-a"
    )

    SwiftUIRails::Reactive::ReactiveAuthorizationContext.stub(:resolve, "session-b") do
      subscribe component_id: @component_id, stream_token: token
    end

    assert subscription.rejected?
    assert_no_streams
  end

  test "rejects a component identifier outside the operations namespace" do
    component_id = "swift-ui-reactive-counter-123456789"
    token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(component_id)

    subscribe component_id: component_id, stream_token: token

    assert subscription.rejected?
    assert_no_streams
  end
end
