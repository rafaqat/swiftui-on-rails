# frozen_string_literal: true

require "test_helper"

class SwiftUIRails::RenderIRHardeningTest < ActiveSupport::TestCase
  IR = SwiftUIRails::RenderIR

  setup do
    @view = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view.extend(SwiftUIRails::Helpers)
  end

  test "portable documents reject executable URLs and embedding surfaces" do
    javascript_link = portable_element("a", [ [ "href", "javascript:alert(document.domain)" ] ])
    error = assert_raises(IR::InvalidStructure) { IR::Validator.validate!(javascript_link) }

    assert_equal "$.root.children[0].props.attribute_pairs[0][1]", error.path
    assert_match(/URL attribute is invalid or unsafe/, error.message)

    iframe = portable_element(
      "iframe",
      [
        [ "src", "/safe" ],
        [ "srcdoc", "<script>alert(1)</script>" ],
        [ "sandbox", "" ],
        [ "title", "Unsafe frame" ]
      ]
    )
    error = assert_raises(IR::InvalidStructure) { IR::Validator.validate!(iframe) }

    assert_equal "$.root.children[0].props.tag", error.path
  end

  test "trusted iframe documents still require the WebView security contract" do
    unsafe = element_document(
      "iframe",
      [
        [ "src", "https://attacker.example/frame" ],
        [ "sandbox", "allow-scripts allow-same-origin" ],
        [ "title", "Unsafe frame" ]
      ]
    )

    error = assert_raises(IR::InvalidStructure) { IR::Validator.validate!(unsafe) }

    assert_match(/URL attribute is invalid or unsafe|origin boundary/, error.message)

    safe = element_document(
      "iframe",
      [
        [ "src", "https://player.vimeo.com/video/123" ],
        [ "sandbox", "allow-presentation allow-scripts" ],
        [ "title", "Demo video" ]
      ]
    )

    assert_same safe, IR::Validator.validate!(safe)
  end

  test "malformed encoded attributes fail validation before rendering" do
    malformed = portable_element("div", [ [ "data-payload", { IR::ValueCodec::PAIRS_KEY => "boom" } ] ])

    error = assert_raises(IR::InvalidStructure) { IR::Validator.validate!(malformed) }

    assert_equal "$.root.children[0].props.attribute_pairs[0][1]", error.path
    assert_match(/ordered-pair value has an invalid shape/, error.message)
  end

  test "nested Rails aria hashes are represented in accessibility metadata" do
    context = SwiftUIRails::DSLContext.new(@view)
    context.instance_eval { progress_view(value: 4, total: 10, label: "Upload") }

    context.flush_elements
    progress = context.last_render_ir.each_node.find { |node| node.kind == "progress_view" }

    assert_equal "Upload", progress.accessibility.fetch("aria-label")
  end

  test "standalone blocks capture concatenation without leaking the ambient output buffer" do
    element = SwiftUIRails::DSL::Element.new(:div, nil, {}) do
      @view.concat(@view.content_tag(:span, "First"))
      @view.concat(@view.content_tag(:span, "Second"))
    end
    element.view_context = @view

    html = element.to_s

    assert_equal "", @view.output_buffer.to_s
    assert_equal %w[First Second], Nokogiri::HTML.fragment(html).css("span").map(&:text)
  end

  test "trusted capability fingerprints distinguish content without serializing it" do
    first = trusted_fragment("<strong>Alpha</strong>".html_safe)
    second = trusted_fragment("<strong>Beta</strong>".html_safe)
    repeated = trusted_fragment("<strong>Alpha</strong>".html_safe)

    refute_equal first.canonical_json, second.canonical_json
    assert_equal first.canonical_json, repeated.canonical_json
    refute_includes first.canonical_json, "<strong>"
    assert_match(/trusted_html:[a-f0-9]{24}:1/, first.canonical_json)
  end

  test "deep documents serialize and round trip through the declared depth boundary" do
    node = IR::Node.new(kind: "text_literal", props: { value: "Deep" })
    55.times do
      node = IR::Node.new(
        kind: "div",
        props: { tag: "div", attribute_pairs: [], paired: true },
        children: [ node ]
      )
    end
    document = IR::Document.new(root: IR::Node.new(kind: "fragment", children: [ node ]))

    canonical = document.canonical_json

    assert_equal document, IR::Document.from_json(canonical)
  end

  private

  def portable_element(tag, pairs)
    element_document(tag, pairs, profile: "portable")
  end

  def element_document(tag, pairs, profile: "trusted")
    IR::Document.new(
      profile: profile,
      root: IR::Node.new(
        kind: "fragment",
        children: [
          IR::Node.new(
            kind: tag,
            props: { tag: tag, attribute_pairs: pairs, paired: true }
          )
        ]
      )
    )
  end

  def trusted_fragment(html)
    session = IR::Session.new(view_context: @view)
    session.document(children: [ session.trusted_html(html) ])
  end
end
