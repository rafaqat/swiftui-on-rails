# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SwiftUIRails::RenderIRPatchSecurityTest < ActiveSupport::TestCase
  IR = SwiftUIRails::RenderIR
  LOCATOR = IR::PatchLocator::ATTRIBUTE

  setup do
    @view = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view.extend(SwiftUIRails::Helpers)
  end

  test "patch trees deterministically refuse trusted capabilities" do
    session = IR::Session.new(view_context: @view)
    root = reactive_root([ session.trusted_html("<strong>Trusted</strong>".html_safe) ])
    document = session.document(children: [ root ])
    html = session.render(document)

    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: html)
    end

    assert_match(/trusted_html/, error.message)
    refute_includes document.metadata.keys, "patch_baseline"
  end

  test "missing duplicate and malformed locators fail closed" do
    document = safe_document
    html = render(document)

    missing = Nokogiri::HTML.fragment(html)
    missing.at_css("#status").remove_attribute(LOCATOR)
    assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: missing.to_html)
    end

    duplicate = Nokogiri::HTML.fragment(html)
    duplicate.at_css("#filler")[LOCATOR] = duplicate.at_css("#status")[LOCATOR]
    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: duplicate.to_html)
    end
    assert_match(/duplicate patch locator/, error.message)

    malformed = Nokogiri::HTML.fragment(html)
    malformed.at_css("#status")[LOCATOR] = "../../unsafe"
    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: malformed.to_html)
    end
    assert_match(/invalid patch locator/, error.message)
  end

  test "duplicate DOM ids and extra parser elements are not patchable" do
    document = safe_document
    duplicate_id = Nokogiri::HTML.fragment(render(document))
    duplicate_id.at_css("#filler")["id"] = "status"

    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: duplicate_id.to_html)
    end
    assert_match(/duplicate DOM id/, error.message)

    extra = Nokogiri::HTML.fragment(render(document))
    extra.at_css("#status").add_child("<em>not emitted by RenderIR</em>")
    assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.build(document: document, html: extra.to_html)
    end
  end

  test "invalid imported IR is validated before locators are generated" do
    unsafe = reactive_document([
      element("a", identity: "unsafe-link", attributes: { "id" => "unsafe-link", "href" => "javascript:alert(1)" })
    ])

    error = assert_raises(IR::InvalidStructure) { render(unsafe) }

    assert_match(/URL attribute is invalid or unsafe/, error.message)
  end

  test "cached trees reject lifecycle attributes and inconsistent content references" do
    payload = patch_tree(safe_document).cache_payload.deep_dup
    payload["root"]["attributes"]["data-sui-snapshot"] = "secret"

    assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.from_cache_payload(payload)
    end

    payload = patch_tree(safe_document).cache_payload.deep_dup
    payload["root"]["content"] << [ "element", "sui-000000000000000000000000" ]
    assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.from_cache_payload(payload)
    end

    payload = patch_tree(safe_document).cache_payload.deep_dup
    payload["root"]["children"].first["text"] = "x" * (IR::PatchTree::MAX_CACHE_BYTES + 1)
    assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.from_cache_payload(payload)
    end
  end

  test "live trees reject arbitrary token-bearing attributes before cache storage" do
    document = reactive_document([
      element(
        "span",
        identity: "status",
        attributes: { "id" => "status", "data-api-token" => "secret" },
        children: [ text("Ready") ]
      )
    ])

    error = assert_raises(IR::PatchTree::Unpatchable) { patch_tree(document) }

    assert_match(/token-bearing attribute/, error.message)
    assert_equal "$.html", error.path
  end

  test "cached trees enforce one aggregate byte budget" do
    payload = patch_tree(safe_document).cache_payload.deep_dup
    payload["root"]["children"].first["text"] = "x" * IR::PatchTree::MAX_CACHE_BYTES

    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.from_cache_payload(payload)
    end

    assert_match(/aggregate byte limit/, error.message)
    assert_equal "$.patch_baseline", error.path
  end

  test "cyclic cache payloads fail closed at the bounded JSON boundary" do
    payload = {}
    payload["cycle"] = payload

    error = assert_raises(IR::PatchTree::Unpatchable) do
      IR::PatchTree.from_cache_payload(payload)
    end

    assert_match(/not JSON-safe/, error.message)
  end

  test "baselines use hashed cache keys and enforce every authorization binding" do
    cache = ActiveSupport::Cache::MemoryStore.new
    tree = patch_tree(safe_document)
    token = IR::PatchBaseline.issue

    IR::PatchBaseline.stub(:cache, cache) do
      stored = IR::PatchBaseline.store(
        token: token,
        tree: tree,
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: "tenant-secret"
      )
      assert stored

      cache_key = "#{IR::PatchBaseline::PURPOSE}:#{Digest::SHA256.hexdigest(token)}"
      raw = cache.read(cache_key)
      serialized = JSON.generate(raw)
      assert raw
      refute_includes cache_key, token
      refute_includes serialized, token
      refute_includes serialized, "tenant-secret"
      refute_includes serialized, "snapshot-token"
      refute_match(IR::PatchBaseline::CAPABILITY_PATTERN, serialized)

      restored = IR::PatchBaseline.fetch(
        token: token,
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: "tenant-secret"
      )
      assert_equal tree.root.cache_payload, restored.root.cache_payload

      assert_nil fetch_baseline(token, component_id: "swift-ui-other-123")
      assert_nil fetch_baseline(token, component_class: "CounterComponent")
      assert_nil fetch_baseline(token, authorization_context: "tenant-other")
    end
  end

  test "baseline tokens are random bounded and expired entries disappear" do
    first = IR::PatchBaseline.issue
    second = IR::PatchBaseline.issue

    assert_match IR::PatchBaseline::TOKEN_PATTERN, first
    assert_match IR::PatchBaseline::TOKEN_PATTERN, second
    refute_equal first, second

    cache = ActiveSupport::Cache::MemoryStore.new
    IR::PatchBaseline.stub(:cache, cache) do
      assert IR::PatchBaseline.store(
        token: first,
        tree: patch_tree(safe_document),
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: nil
      )

      travel(IR::PatchBaseline::DEFAULT_EXPIRY + 1.second) do
        assert_nil IR::PatchBaseline.fetch(
          token: first,
          component_id: "swift-ui-probe-123",
          component_class: "ReactiveCounterComponent",
          authorization_context: nil
        )
      end
    end
  end

  test "an anonymous baseline remains valid when Rails establishes a session before the action" do
    cache = ActiveSupport::Cache::MemoryStore.new
    token = IR::PatchBaseline.issue

    IR::PatchBaseline.stub(:cache, cache) do
      assert IR::PatchBaseline.store(
        token: token,
        tree: patch_tree(safe_document),
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: nil
      )

      restored = IR::PatchBaseline.fetch(
        token: token,
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: "new-rails-session"
      )
      assert_instance_of IR::PatchTree, restored
    end
  end

  test "oversized or capability-shaped cache payloads are never stored or restored" do
    cache = ActiveSupport::Cache::MemoryStore.new
    oversized_document = reactive_document([
      element("p", identity: "large", attributes: { "id" => "large" }, children: [ text("x" * 600.kilobytes) ])
    ])
    capability_document = reactive_document([
      element(
        "p",
        identity: "probe",
        attributes: { "id" => "probe" },
        children: [ text("trusted_html:0123456789abcdef01234567:1") ]
      )
    ])

    IR::PatchBaseline.stub(:cache, cache) do
      refute IR::PatchBaseline.store(
        token: IR::PatchBaseline.issue,
        tree: patch_tree(oversized_document),
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: nil
      )
      refute IR::PatchBaseline.store(
        token: IR::PatchBaseline.issue,
        tree: patch_tree(capability_document),
        component_id: "swift-ui-probe-123",
        component_class: "ReactiveCounterComponent",
        authorization_context: nil
      )
    end
  end

  private

  def render(document)
    IR::HTMLRenderer.call(document, view_context: @view).to_s
  end

  def patch_tree(document)
    IR::PatchTree.build(document: document, html: render(document))
  end

  def fetch_baseline(token, **overrides)
    IR::PatchBaseline.fetch(
      token: token,
      component_id: "swift-ui-probe-123",
      component_class: "ReactiveCounterComponent",
      authorization_context: "tenant-secret",
      **overrides
    )
  end

  def safe_document
    reactive_document([
      element("span", identity: "status", attributes: { "id" => "status" }, children: [ text("Ready") ]),
      element("p", identity: "filler", attributes: { "id" => "filler" }, children: [ text("Stable") ])
    ])
  end

  def reactive_document(children)
    IR::Document.new(root: IR::RuntimeNodeFactory.fragment([ reactive_root(children) ]))
  end

  def reactive_root(children)
    element(
      "div",
      kind: "reactive_container",
      identity: "swift-ui-probe-123",
      attributes: {
        "id" => "swift-ui-probe-123",
        "data-sui-root" => "1",
        "data-sui-id" => "swift-ui-probe-123",
        "data-sui-component" => "ReactiveCounterComponent",
        "data-sui-snapshot" => "snapshot-secret",
        "data-sui-stream" => "stream-secret"
      },
      children: children
    )
  end

  def text(value)
    IR::RuntimeNodeFactory.text(value)
  end

  def element(tag, identity: nil, attributes: {}, children: [], kind: tag)
    pairs = attributes.map.with_index do |(name, value), index|
      [ name, IR::ValueCodec.encode(value, path: "$.attributes[#{index}]") ]
    end
    IR::RuntimeNodeFactory.element(
      kind: kind,
      tag: tag,
      attribute_pairs: pairs,
      paired: true,
      children: children,
      identity: identity
    )
  end
end
