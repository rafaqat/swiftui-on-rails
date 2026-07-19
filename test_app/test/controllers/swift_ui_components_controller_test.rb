# frozen_string_literal: true

require "test_helper"

class SwiftUiComponentsControllerTest < ActionDispatch::IntegrationTest
  test "encrypted snapshots preserve bindings and component identity across updates" do
    html = ApplicationController.render(ReactiveCounterComponent.new(label: "Round trip"), layout: false)
    root = Nokogiri::HTML.fragment(html).at_css("[data-sui-root='1']")
    component_id = root["id"]
    assert_nil root["data-swift-ui-reactive-props-value"]

    post swift_ui_component_update_path,
      params: {
        component_id: component_id,
        component_class: "ReactiveCounterComponent",
        stream_token: root["data-sui-stream"],
        snapshot_token: root["data-sui-snapshot"],
        props: { label: "browser cannot replace signed props" },
        changes: { "binding.step" => { new: 3 } }
      },
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "application/json"
      },
      as: :json

    assert_response :success
    payload = response.parsed_body
    updated_root = Nokogiri::HTML.fragment(payload.fetch("html")).at_css("[data-sui-root='1']")
    assert_equal component_id, updated_root["id"]
    assert_equal "3", updated_root.at_css("input[name='step']")["value"]
    assert_includes updated_root.text, "Round trip"
    refute_includes updated_root.text, "browser cannot replace signed props"
    assert payload.fetch("snapshot_token").present?
    assert payload.fetch("stream_token").present?
    refute payload.key?("props")
  end

  test "a negotiated update returns a bounded keyed patch instead of full html" do
    with_patch_cache do
      root = reactive_counter_root
      snapshot = SwiftUIRails::Reactive::ReactiveComponentSnapshot.verified(
        root["data-sui-snapshot"],
        component_id: root["id"],
        component_class: root["data-sui-component"]
      )
      assert snapshot.fetch("patch_baseline").present?

      post_reactive_update(
        update_params_for(root, changes: { "binding.step" => { new: 3 } })
          .merge(render_patch_version: 1)
      )

      assert_response :success
      payload = response.parsed_body
      patch = payload.fetch("patch")
      assert_equal 1, patch.fetch("version")
      assert_equal root["id"], patch.fetch("component_id")
      assert_operator patch.fetch("operations").length, :>, 0
      assert patch.fetch("operations").all? { |operation| operation.fetch("key").present? || operation.fetch("parent_key").present? }
      refute payload.key?("html")
      assert_operator JSON.generate(patch).bytesize, :<, 8.kilobytes
    end
  end

  test "a missing server baseline falls back to the complete html contract" do
    root = reactive_counter_root

    SwiftUIRails::RenderIR::PatchBaseline.stub(:fetch, nil) do
      post_reactive_update(
        update_params_for(root, changes: { "binding.step" => { new: 2 } })
          .merge(render_patch_version: 1)
      )
    end

    assert_response :success
    payload = response.parsed_body
    assert payload.fetch("html").include?("data-sui-root=\"1\"")
    refute payload.key?("patch")
  end

  test "a supplied invalid snapshot is rejected" do
    component_id = "swift-ui-reactive-counter-component-123"

    post swift_ui_component_update_path,
      params: {
        component_id: component_id,
        component_class: "ReactiveCounterComponent",
        stream_token: SwiftUIRails::Reactive::ReactiveStreamToken.generate(component_id),
        snapshot_token: "not-a-valid-snapshot",
        changes: {}
      },
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "application/json"
      },
      as: :json

    assert_response :forbidden
    assert_equal "Unauthorized component snapshot", response.parsed_body.fetch("error")
  end

  test "a stream token without an encrypted snapshot cannot instantiate a component" do
    component_id = "swift-ui-counter-component-123"
    stream_token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(component_id)

    post swift_ui_component_update_path,
      params: {
        component_id: component_id,
        component_class: "CounterComponent",
        stream_token: stream_token,
        changes: { "prop.initial_count" => { new: 2 } }
      },
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "application/json"
      },
      as: :json

    assert_response :forbidden
    assert_equal "Unauthorized component snapshot", response.parsed_body.fetch("error")
  end

  test "the reactive route rejects a capability for another component" do
    post swift_ui_component_update_path,
      params: {
        component_id: "swift-ui-counter-component-123",
        component_class: "CounterComponent",
        stream_token: SwiftUIRails::Reactive::ReactiveStreamToken.generate("swift-ui-other-component-456"),
        props: {}
      },
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "application/json"
      },
      as: :json

    assert_response :forbidden
  end

  test "an encrypted snapshot is single use and replay returns a conflict" do
    root = reactive_counter_root
    request_params = update_params_for(root, changes: { "binding.step" => { new: 4 } })

    post_reactive_update(request_params)
    assert_response :success

    post_reactive_update(request_params)
    assert_response :conflict
    assert_equal "Component changed; refresh and try again", response.parsed_body.fetch("error")
  end

  test "nil cannot erase a non-nullable numeric binding" do
    root = reactive_counter_root

    post_reactive_update(
      update_params_for(root, changes: { "binding.step" => { new: nil } })
    )

    assert_response :success
    updated = Nokogiri::HTML.fragment(response.parsed_body.fetch("html"))
    assert_equal "1", updated.at_css("input[name='step']")["value"]
  end

  test "oversized and over-nested updates are rejected before consuming the snapshot" do
    root = reactive_counter_root
    original_params = update_params_for(root, changes: { "binding.step" => { new: 2 } })
    oversized = update_params_for(
      root,
      changes: { "binding.step" => { new: "x" * 257.kilobytes } }
    )

    post_reactive_update(oversized)
    assert_response :content_too_large

    nested = 8.times.reduce("leaf") { |value, index| { "level_#{index}" => value } }
    post_reactive_update(update_params_for(root, changes: { "binding.step" => { new: nested } }))
    assert_response :unprocessable_entity
    assert_equal "Reactive update is too complex", response.parsed_body.fetch("error")

    post_reactive_update(original_params)
    assert_response :success
  end

  test "rate limited updates do not consume the encrypted snapshot" do
    root = reactive_counter_root
    request_params = update_params_for(root, changes: { "binding.step" => { new: 2 } })

    Rails.cache.stub(:increment, 241) do
      post_reactive_update(request_params)
    end
    assert_response :too_many_requests

    post_reactive_update(request_params)
    assert_response :success
  end

  private

  def reactive_counter_root
    html = ApplicationController.render(ReactiveCounterComponent.new(label: "Security probe"), layout: false)
    Nokogiri::HTML.fragment(html).at_css("[data-sui-root='1']")
  end

  def update_params_for(root, changes:)
    {
      component_id: root["id"],
      component_class: root["data-sui-component"],
      stream_token: root["data-sui-stream"],
      snapshot_token: root["data-sui-snapshot"],
      changes: changes
    }
  end

  def post_reactive_update(params)
    post swift_ui_component_update_path,
      params: params,
      headers: {
        "X-Requested-With" => "XMLHttpRequest",
        "Accept" => "application/json"
      },
      as: :json
  end

  def with_patch_cache(&block)
    cache = ActiveSupport::Cache::MemoryStore.new
    SwiftUIRails::RenderIR::PatchBaseline.stub(:cache, cache, &block)
  end
end
