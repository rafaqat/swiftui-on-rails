# frozen_string_literal: true

require "test_helper"
require "benchmark"

class SwiftUIRails::RenderIRPatchPerformanceTest < ActiveSupport::TestCase
  IR = SwiftUIRails::RenderIR

  setup do
    @view = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view.extend(SwiftUIRails::Helpers)
  end

  test "one rotated key among one thousand children plans one move within the patch budget" do
    identities = Array.new(1_000) { |index| index.to_s }
    old_tree, = tree_for(identities)
    new_tree, full_html = tree_for(identities.rotate)

    result = nil
    GC.start
    allocations_before = GC.stat.fetch(:total_allocated_objects)
    elapsed = Benchmark.realtime do
      result = IR::PatchBuilder.call(old_tree: old_tree, new_tree: new_tree, full_html: full_html)
    end
    allocations = GC.stat.fetch(:total_allocated_objects) - allocations_before

    assert_predicate result, :patch?
    assert_equal [ "move" ], result.operations.map { |operation| operation.fetch("op") }
    assert_operator JSON.generate(result.to_h(component_id: "swift-ui-benchmark-123")).bytesize,
      :<, full_html.bytesize / 20
    assert_operator elapsed, :<, 1.0,
      "1,000-key planning took #{elapsed.round(4)}s"
    assert_operator allocations, :<, 250_000,
      "1,000-key planning allocated #{allocations} objects"
  end

  test "operation explosions deterministically fall back before transport" do
    ids = Array.new(IR::PatchBuilder::MAX_OPERATIONS + 1) { |index| index.to_s }
    old_tree, = tree_for(ids, class_name: "before")
    new_tree, full_html = tree_for(ids, class_name: "after")

    result = IR::PatchBuilder.call(old_tree: old_tree, new_tree: new_tree, full_html: full_html)

    assert_predicate result, :fallback?
    assert_equal :budget_exceeded, result.reason
    assert_empty result.operations
  end

  private

  def tree_for(identities, class_name: nil)
    rows = identities.map do |identity|
      attributes = { "id" => "row-#{identity}" }
      attributes["class"] = class_name if class_name
      element(
        "li",
        identity: "row-#{identity}",
        attributes: attributes,
        children: [ IR::RuntimeNodeFactory.text(identity) ]
      )
    end
    list = element("ul", identity: "rows", attributes: { "id" => "rows" }, children: rows)
    root = element(
      "div",
      kind: "reactive_container",
      identity: "swift-ui-benchmark-123",
      attributes: { "id" => "swift-ui-benchmark-123", "data-swift-ui-reactive" => "true" },
      children: [ list ]
    )
    document = IR::Document.new(root: IR::RuntimeNodeFactory.fragment([ root ]))
    html = IR::HTMLRenderer.call(document, view_context: @view).to_s
    [ IR::PatchTree.build(document: document, html: html), html ]
  end

  def element(tag, identity:, attributes:, children:, kind: tag)
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
