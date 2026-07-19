# frozen_string_literal: true

require "test_helper"

class SwiftUIRails::RenderIRTest < ActiveSupport::TestCase
  IR = SwiftUIRails::RenderIR

  test "builds an immutable resolved semantic document" do
    input = +"Operations"
    node = IR::Node.new(
      kind: "vstack",
      props: { alignment: "leading", spacing: 12 },
      identity: "operations-panel",
      accessibility: { role: "region", label: input },
      modifiers: [
        IR::Modifier.new(name: "padding", arguments: [ 6 ]),
        IR::Modifier.new(name: "background", keywords: { style: "surface" })
      ],
      children: [ IR::Node.new(kind: "text", props: { content: input }) ]
    )
    document = IR::Document.new(
      root: node,
      profile: "portable",
      language_version: "1.0.0",
      metadata: { component: "OperationsComponent" }
    )

    input.replace("Changed")

    assert_equal IR::SCHEMA, document.schema
    assert_equal IR::VERSION, document.version
    assert_equal "portable", document.profile
    assert_equal "1.0.0", document.language_version
    assert_equal "Operations", document.root.accessibility.fetch("label")
    assert_equal "operations-panel", document.root.identity
    assert_equal %w[padding background], document.root.modifiers.map(&:name)
    assert_equal %w[vstack text], document.each_node.map(&:kind)
    assert document.frozen?
    assert document.root.frozen?
    assert document.root.props.frozen?
    assert document.root.modifiers.frozen?
    assert document.root.children.frozen?
    assert document.to_h.frozen?
    assert_raises(FrozenError) { document.root.children << node }
    assert_raises(FrozenError) { document.root.props["spacing"] = 20 }
  end

  test "canonical JSON is deterministic and round trips with typed records" do
    first = IR::Document.new(
      root: {
        props: { zebra: true, alpha: { z: 2, a: 1 } },
        kind: "text",
        modifiers: [ { keywords: { z: 2, a: 1 }, name: "font", arguments: [ "body" ] } ]
      },
      metadata: { z: "last", a: "first" }
    )
    second = IR::Document.from_h(
      "version" => 1,
      "root" => {
        "modifiers" => [ { "arguments" => [ "body" ], "name" => "font", "keywords" => { "a" => 1, "z" => 2 } } ],
        "kind" => "text",
        "props" => { "alpha" => { "a" => 1, "z" => 2 }, "zebra" => true }
      },
      "schema" => IR::SCHEMA,
      "profile" => "trusted",
      "language_version" => nil,
      "metadata" => { "a" => "first", "z" => "last" }
    )

    assert_equal first, second
    assert_equal first.canonical_json, second.canonical_json
    assert_equal first, IR::Document.from_json(first.canonical_json)
    assert_equal first.canonical_json, IR.canonical_json(first)
    assert_equal first.root.to_h, JSON.parse(first.root.canonical_json)
    assert_match(/\A\{"language_version":/, first.canonical_json)
  end

  test "preserves modifier and child order while sorting only object keys" do
    document = IR.document(
      root: IR.node(
        kind: "hstack",
        modifiers: [
          IR.modifier(name: "padding", arguments: [ 4 ]),
          IR.modifier(name: "background", arguments: [ "surface" ]),
          IR.modifier(name: "padding", arguments: [ 2 ])
        ],
        children: [
          IR.node(kind: "text", props: { content: "First" }),
          IR.node(kind: "text", props: { content: "Second" })
        ]
      )
    )

    assert_equal %w[padding background padding], document.root.modifiers.map(&:name)
    assert_equal %w[First Second], document.root.children.map { |child| child.props.fetch("content") }
  end

  test "rejects executable rendered and otherwise non JSON-native values" do
    invalid_values = [
      -> { "execute me" },
      Object.new,
      :symbol_value,
      ActiveSupport::SafeBuffer.new("<strong>already rendered</strong>")
    ]

    invalid_values.each do |value|
      error = assert_raises(IR::InvalidValue) do
        IR::Node.new(kind: "text", props: { content: value })
      end

      assert_equal "$.props.content", error.path
      assert_match(/JSON-native|plain String/, error.message)
    end
  end

  test "rejects cycles duplicate normalized keys invalid floats and excessive depth" do
    cyclic = []
    cyclic << cyclic

    error = assert_raises(IR::InvalidValue) { IR::Node.new(kind: "list", props: { items: cyclic }) }
    assert_equal "$.props.items[0]", error.path
    assert_match(/cycles/, error.message)

    error = assert_raises(IR::InvalidValue) do
      IR::Node.new(kind: "text", props: { "content" => "first", content: "second" })
    end
    assert_equal "$.props", error.path
    assert_match(/duplicate key `content`/, error.message)

    error = assert_raises(IR::InvalidValue) do
      IR::Node.new(kind: "progress", props: { value: Float::NAN })
    end
    assert_equal "$.props.value", error.path
    assert_match(/finite/, error.message)

    nested = []
    (IR::Normalizer::MAX_DEPTH + 1).times { nested = [ nested ] }
    assert_raises(IR::InvalidValue) { IR::Node.new(kind: "list", props: { items: nested }) }
  end

  test "rejects already-UTF-8-tagged strings that carry invalid bytes" do
    # encode!(UTF-8) is a no-op on a UTF-8-tagged string, so the validity
    # check — not the transcode — is what keeps malformed bytes out of the IR.
    malformed = "bad\xFF\xFEbytes".dup.force_encoding("UTF-8")
    refute malformed.valid_encoding?

    error = assert_raises(IR::InvalidValue) do
      IR::Node.new(kind: "text", props: { content: malformed })
    end
    assert_equal "$.props.content", error.path
    assert_match(/valid UTF-8/, error.message)
  end

  test "rejects malformed records unknown keys schemas and versions precisely" do
    error = assert_raises(IR::InvalidStructure) do
      IR::Node.from_h(kind: "text", html: "<strong>unsafe</strong>")
    end
    assert_equal "$", error.path
    assert_match(/unknown key `html`/, error.message)

    error = assert_raises(IR::InvalidStructure) { IR::Modifier.from_h(arguments: []) }
    assert_equal "$", error.path
    assert_match(/missing required key `name`/, error.message)

    attributes = valid_document_hash
    attributes["schema"] = "some-other-schema"
    error = assert_raises(IR::InvalidStructure) { IR::Document.from_h(attributes) }
    assert_equal "$.schema", error.path

    attributes = valid_document_hash
    attributes["version"] = 99
    error = assert_raises(IR::UnsupportedVersion) { IR::Document.from_h(attributes) }
    assert_equal "$.version", error.path
  end

  test "defensively copies mutable input and rejects invalid JSON" do
    props = { content: +"Original", details: [ "one" ] }
    document = IR::Document.new(root: IR::Node.new(kind: "text", props: props))

    props[:content].replace("Changed")
    props[:details] << "two"

    assert_equal "Original", document.root.props.fetch("content")
    assert_equal [ "one" ], document.root.props.fetch("details")

    error = assert_raises(IR::InvalidValue) { IR::Document.from_json("{not-json") }
    assert_equal "$", error.path
    assert_match(/not valid JSON/, error.message)
  end

  private

  def valid_document_hash
    {
      "schema" => IR::SCHEMA,
      "version" => IR::VERSION,
      "profile" => "trusted",
      "language_version" => nil,
      "metadata" => {},
      "root" => { "kind" => "text" }
    }
  end
end
