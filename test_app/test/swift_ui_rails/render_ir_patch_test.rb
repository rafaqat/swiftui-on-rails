# frozen_string_literal: true

require "test_helper"

class SwiftUIRails::RenderIRPatchTest < ActiveSupport::TestCase
  IR = SwiftUIRails::RenderIR
  LOCATOR = IR::PatchLocator::ATTRIBUTE

  setup do
    @view = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view.extend(SwiftUIRails::Helpers)
  end

  test "reactive rendering injects deterministic locators without changing RenderIR" do
    first = list_document(%w[a b])
    second = list_document(%w[b a])
    first_json = first.canonical_json

    first_html = render(first)
    second_html = render(second)
    first_dom = fragment(first_html)
    second_dom = fragment(second_html)

    assert first_dom.css("*").all? { |element| element[LOCATOR].match?(IR::PatchLocator::KEY_PATTERN) }
    assert_equal first_json, first.canonical_json
    refute_includes first_json, LOCATOR

    %w[item-a item-b].each do |id|
      assert_equal first_dom.at_css("##{id}")[LOCATOR], second_dom.at_css("##{id}")[LOCATOR]
      assert_equal first_dom.at_css("##{id} span")[LOCATOR], second_dom.at_css("##{id} span")[LOCATOR]
    end
  end

  test "non-reactive documents do not receive patch locators" do
    document = document_with_root(element("div", identity: "ordinary", attributes: { "id" => "ordinary" }))

    refute_includes render(document), LOCATOR
    assert_empty IR::PatchLocator.for(document)
  end

  test "identities are scoped by their keyed ancestors" do
    groups = %w[first second].map do |group|
      element(
        "section",
        identity: group,
        attributes: { "id" => group },
        children: [ element("span", identity: "repeated", children: [ text(group) ]) ]
      )
    end
    first_document = reactive_document(groups)
    second_document = reactive_document(groups.reverse)
    first_dom = fragment(render(first_document))
    second_dom = fragment(render(second_document))

    first_keys = %w[first second].map { |id| first_dom.at_css("##{id} span")[LOCATOR] }

    assert_equal first_keys.uniq, first_keys
    %w[first second].each do |id|
      assert_equal first_dom.at_css("##{id} span")[LOCATOR], second_dom.at_css("##{id} span")[LOCATOR]
    end
  end

  test "patch tree is concrete but its cache payload omits html and lifecycle capabilities" do
    token = "server-secret-snapshot"
    document = reactive_document([
      element("span", identity: "status", attributes: { "id" => "status" }, children: [ text("Ready") ])
    ], root_attributes: {
      "id" => "swift-ui-probe-123",
      "data-sui-root" => "1",
      "data-sui-id" => "swift-ui-probe-123",
      "data-sui-component" => "ReactiveCounterComponent",
      "data-sui-snapshot" => token,
      "data-sui-stream" => "stream-secret"
    })
    html = render(document)

    tree = IR::PatchTree.build(document: document, html: html)
    payload = tree.cache_payload
    serialized = JSON.generate(payload)

    assert tree.root.html.present?
    assert_equal "Ready", tree.root.children.first.text
    refute_includes tree.root.attributes.keys, LOCATOR
    refute_includes serialized, "html"
    refute_includes serialized, token
    refute_includes serialized, "stream-secret"
    refute_includes serialized, "snapshot-token"

    restored = IR::PatchTree.from_cache_payload(payload)
    assert_nil restored.root.html
    assert_equal tree.root.cache_payload, restored.root.cache_payload
    assert_predicate restored.root.cache_payload, :frozen?
    assert_predicate restored.root.attributes.keys.first, :frozen?
    assert_predicate restored.root.content.first.last, :frozen?
  end

  test "attribute and leaf text changes produce the fixed v1 operation shape" do
    old_document = status_document(text: "Waiting", class_name: "muted")
    new_document = status_document(text: "Ready", class_name: "success")
    old_tree = patch_tree(old_document)
    new_html = render(new_document)
    new_tree = IR::PatchTree.build(document: new_document, html: new_html)

    result = IR::PatchBuilder.call(old_tree: old_tree, new_tree: new_tree, full_html: new_html)
    status_key = element_by_id(new_tree, "status").key

    assert_predicate result, :patch?
    assert_equal [
      {
        "attributes" => { "class" => "success", "id" => "status" },
        "key" => status_key,
        "op" => "attributes"
      },
      { "key" => status_key, "op" => "text", "value" => "Ready" }
    ], result.operations
    assert_equal({
      "component_id" => "swift-ui-probe-123",
      "operations" => result.operations,
      "version" => 1
    }, result.to_h(component_id: "swift-ui-probe-123"))
  end

  test "keyed children use LIS reconciliation for remove insert and move" do
    old_document = ordered_document(%w[a b c d])
    new_document = ordered_document(%w[c a e d])
    old_tree = patch_tree(old_document)
    new_html = render(new_document)
    new_tree = IR::PatchTree.build(document: new_document, html: new_html)

    result = IR::PatchBuilder.call(old_tree: old_tree, new_tree: new_tree, full_html: new_html)
    keys = %w[a c d e].to_h { |id| [ id, element_by_id(new_tree, "row-#{id}").key ] }
    removed_b = element_by_id(old_tree, "row-b").key
    list_key = element_by_id(new_tree, "rows").key

    assert_predicate result, :patch?
    assert_equal 3, result.operations.length
    assert_equal({ "key" => removed_b, "op" => "remove" }, result.operations[0])
    assert_equal "insert", result.operations[1].fetch("op")
    assert_equal list_key, result.operations[1].fetch("parent_key")
    assert_equal keys.fetch("d"), result.operations[1].fetch("before_key")
    assert_includes result.operations[1].fetch("html"), %(id="row-e")
    assert_equal({
      "before_key" => keys.fetch("a"),
      "key" => keys.fetch("c"),
      "op" => "move",
      "parent_key" => list_key
    }, result.operations[2])
  end

  test "a keyed child that both moves and gains children keeps its move operation" do
    # Regression: replace_last_operations_for must supersede only the same-call
    # attributes op, never the move the parent already emitted. Otherwise a
    # reordered list item that gains a nested section (Flightplan cards, Relay
    # threads) is left at its old DOM position.
    old_document = ordered_document(%w[a b c])
    new_document = reactive_document([
      element("ul", identity: "rows", attributes: { "id" => "rows" }, children: [
        ordered_row("b"),
        ordered_row("c"),
        element("li", identity: "row-a", attributes: { "id" => "row-a" },
                children: [ element("span", attributes: { "id" => "detail-a" }, children: [ text("a") ]) ])
      ]),
      element("p", identity: "filler", attributes: { "id" => "filler" }, children: [ text("stable" * 600) ])
    ])

    new_html = render(new_document)
    new_tree = IR::PatchTree.build(document: new_document, html: new_html)
    result = IR::PatchBuilder.call(old_tree: patch_tree(old_document), new_tree: new_tree, full_html: new_html)
    row_a = element_by_id(new_tree, "row-a").key

    assert_predicate result, :patch?
    move = result.operations.find { |operation| operation["op"] == "move" && operation["key"] == row_a }
    replace = result.operations.find { |operation| operation["op"] == "replace" && operation["key"] == row_a }

    assert move, "expected row-a to keep its move operation (was clobbered by the replace)"
    assert replace, "expected row-a to be replaced now that it has element children"
    assert_nil move.fetch("before_key"), "row-a moves to the end of the list"
  end

  test "tag changes replace a keyed descendant but never the reactive root" do
    old_document = swap_document(root_tag: "div", child_tag: "span")
    descendant_document = swap_document(root_tag: "div", child_tag: "strong")
    root_document = swap_document(root_tag: "section", child_tag: "span")

    descendant_html = render(descendant_document)
    descendant_result = IR::PatchBuilder.call(
      old_tree: patch_tree(old_document),
      new_tree: IR::PatchTree.build(document: descendant_document, html: descendant_html),
      full_html: descendant_html
    )

    assert_predicate descendant_result, :patch?
    assert_predicate descendant_result.operations, :one?
    assert_equal "replace", descendant_result.operations.first.fetch("op")
    assert_includes descendant_result.operations.first.fetch("html"), "<strong"

    root_html = render(root_document)
    root_result = IR::PatchBuilder.call(
      old_tree: patch_tree(old_document),
      new_tree: IR::PatchTree.build(document: root_document, html: root_html),
      full_html: root_html
    )

    assert_predicate root_result, :fallback?
    assert_equal :root_replace_required, root_result.reason
  end

  test "patches fall back when their encoded response is not smaller than full HTML" do
    old_document = status_document(text: "A", class_name: "a", include_filler: false)
    new_document = status_document(text: "B", class_name: "b", include_filler: false)

    result = IR::PatchBuilder.call(
      old_tree: patch_tree(old_document),
      new_tree: patch_tree(new_document),
      full_html: "x"
    )

    assert_predicate result, :fallback?
    assert_equal :patch_not_smaller, result.reason
    assert_raises(IR::PatchBuilder::UnsafeDiff) do
      result.to_h(component_id: "swift-ui-probe-123")
    end
  end

  test "patch byte budgets are checked once after planning and fail closed" do
    old_document = status_document(text: "A", class_name: "status", include_filler: false)
    new_document = status_document(
      text: "x" * (IR::PatchBuilder::MAX_PATCH_BYTES + 1),
      class_name: "status",
      include_filler: false
    )
    new_html = render(new_document)

    result = IR::PatchBuilder.call(
      old_tree: patch_tree(old_document),
      new_tree: patch_tree(new_document),
      full_html: new_html
    )

    assert_predicate result, :fallback?
    assert_equal :budget_exceeded, result.reason
    assert_empty result.operations
  end

  test "every planner fallback exposes a symbolic reason" do
    valid_tree = patch_tree(status_document(text: "A", class_name: "a"))
    changed_root = patch_tree(
      reactive_document([], root_attributes: { "id" => "swift-ui-other-123", "data-swift-ui-reactive" => "true" })
    )
    results = [
      IR::PatchBuilder.call(old_tree: Object.new, new_tree: valid_tree, full_html: "html"),
      IR::PatchBuilder.call(old_tree: valid_tree, new_tree: changed_root, full_html: "html"),
      IR::PatchBuilder.call(old_tree: valid_tree, new_tree: valid_tree, full_html: "")
    ]

    assert results.all?(&:fallback?)
    assert results.all? { |result| result.reason.is_a?(Symbol) }
    assert_equal %i[invalid_tree root_replace_required empty_full_html], results.map(&:reason)
  end

  private

  def render(document, capabilities: IR::CapabilityRegistry.new)
    IR::HTMLRenderer.call(document, view_context: @view, capabilities: capabilities).to_s
  end

  def fragment(html)
    Nokogiri::HTML.fragment(html)
  end

  def patch_tree(document)
    IR::PatchTree.build(document: document, html: render(document))
  end

  def element_by_id(tree, id)
    tree.each_element.find { |candidate| candidate.attributes["id"] == id }
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

  def document_with_root(root)
    IR::Document.new(root: IR::RuntimeNodeFactory.fragment([ root ]))
  end

  def reactive_document(children, root_attributes: nil, root_tag: "div")
    attributes = root_attributes || { "id" => "swift-ui-probe-123", "data-swift-ui-reactive" => "true" }
    document_with_root(
      element(
        root_tag,
        kind: "reactive_container",
        identity: "swift-ui-probe-123",
        attributes: attributes,
        children: children
      )
    )
  end

  def list_document(order)
    items = order.map do |id|
      element(
        "article",
        identity: "item-#{id}",
        attributes: { "id" => "item-#{id}" },
        children: [ element("span", children: [ text(id.upcase) ]) ]
      )
    end
    reactive_document([
      element("div", identity: "items", attributes: { "id" => "items" }, children: items)
    ])
  end

  def status_document(text:, class_name:, include_filler: true)
    children = [
      element(
        "span",
        identity: "status",
        attributes: { "id" => "status", "class" => class_name },
        children: [ self.text(text) ]
      )
    ]
    if include_filler
      children << element(
        "p",
        identity: "unchanged",
        attributes: { "id" => "unchanged" },
        children: [ self.text("x" * 2_000) ]
      )
    end
    reactive_document(children)
  end

  def ordered_row(id)
    element("li", identity: "row-#{id}", attributes: { "id" => "row-#{id}" }, children: [ text(id) ])
  end

  def ordered_document(order)
    rows = order.map { |id| ordered_row(id) }
    reactive_document([
      element("ul", identity: "rows", attributes: { "id" => "rows" }, children: rows),
      element(
        "p",
        identity: "filler",
        attributes: { "id" => "filler" },
        children: [ text("stable" * 600) ]
      )
    ])
  end

  def swap_document(root_tag:, child_tag:)
    reactive_document(
      [
        element(
          child_tag,
          identity: "swap",
          attributes: { "id" => "swap" },
          children: [ text("Same") ]
        ),
        element(
          "p",
          identity: "filler",
          attributes: { "id" => "filler" },
          children: [ text("stable" * 600) ]
        )
      ],
      root_tag: root_tag
    )
  end
end
