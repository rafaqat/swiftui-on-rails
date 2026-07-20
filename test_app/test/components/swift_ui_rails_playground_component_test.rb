# frozen_string_literal: true

require "test_helper"
require "prism"

class SwiftUiRailsPlaygroundComponentTest < ViewComponent::TestCase
  COMPONENT_SOURCE_PATH = Rails.root.join("app/components/swift_ui_rails_playground_component.rb")
  PLAYGROUND_JAVASCRIPT_PATH = Rails.root.join("app/javascript/controllers/playground_controller.js")

  setup do
    @example = Showcase::Playground::Examples.find("product-catalog")
    @result = Showcase::Playground::Runner.call(
      source: @example.source,
      data_json: @example.data_json,
      view_context: ApplicationController.new.view_context
    )
  end

  test "dogfoods SwiftUI Rails for a complete server-owned IDE shell" do
    assert_operator SwiftUiRailsPlaygroundComponent, :<, SwiftUIRails::Component::Base

    render_inline(component)

    assert_selector "#swift-rails-playground[data-playground-mode='server-round-trip']"
    assert_selector "[data-swift-ui-appearance='playground-shell']"
    assert_selector "form#playground-run-form[action='/showcase/playground/run'][method='POST']"
    assert_selector "#playground-run[type='submit'][form='playground-run-form']", text: "Run on Rails"
    assert_selector "#playground-source[name='source'][spellcheck='false'][wrap='off']"
    assert_selector "#playground-data[name='data_json'][spellcheck='false'][wrap='off']"
    assert_selector "#playground-preview[src='/showcase/playground/preview?example=product-catalog'][sandbox='allow-same-origin']"
    assert_selector "#playground-preview[sandbox*='allow-scripts']", count: 0
    assert_selector "[data-swift-ui-appearance='playground-example-row']", count: Showcase::Playground::Examples.all.length
    assert_selector "#playground-diagnostics-panel"
    assert_selector "#playground-data-inspector-panel"
    assert_selector "#playground-ir-panel"
    assert_selector "#playground-language-panel"
    assert_selector "#playground-assistant-panel"
    assert_selector "a[href='/showcase/playground/language']", minimum: 1
    assert_selector "a[href='/showcase/playground/reliability']", visible: :all
    assert_text "One cognitive model"
    assert_text "Server round trips · no application JavaScript"

    assert_selector "[data-controller], [data-action], [data-playground-target]", count: 0
    assert_selector "[data-sui-actions], [data-sui-binding]", count: 0
    refute_path_exists PLAYGROUND_JAVASCRIPT_PATH
  end

  test "dogfood source has no escape hatch or application JavaScript metadata" do
    source = COMPONENT_SOURCE_PATH.read
    parsed = Prism.parse(source)
    assert_empty parsed.errors

    calls = all_nodes(parsed.value).grep(Prism::CallNode).map(&:name)
    refute_includes calls, :tw

    raw_class_arguments = all_nodes(parsed.value).grep(Prism::AssocNode).select do |node|
      node.key.is_a?(Prism::SymbolNode) && node.key.unescaped == "class" &&
        (node.value.is_a?(Prism::StringNode) || node.value.is_a?(Prism::InterpolatedStringNode))
    end
    assert_empty raw_class_arguments

    refute_match(/\b(?:content_tag|safe_join|raw)\s*\(|\.html_safe\b|\btag\.[a-z_]+/, source)
    refute_match(/\.(?:stimulus_controller|stimulus_action|stimulus_target|stimulus_param)\b/, source)
    refute_match(/\b(?:playground_target|controller:|action:)\b|event->controller#method/, source)
    refute_match(/\b(?:localStorage|querySelector|classList|innerHTML|outerHTML)\b|\beval\s*\(/, source)
    assert_includes source, "secure_form("
    assert_includes source, "web_view("
    assert_includes source, "disclosure_group("
  end

  test "renders canonical authoring IR and RenderIR as escaped readonly text" do
    render_inline(component)

    assert_selector "label[for='playground-authoring-ir']", text: "Authoring IR canonical JSON", visible: :all
    assert_selector "label[for='playground-render-ir']", text: "Resolved RenderIR canonical JSON", visible: :all
    assert_selector "#playground-authoring-ir[readonly][spellcheck='false'][wrap='off']", visible: :all
    assert_selector "#playground-render-ir[readonly][spellcheck='false'][wrap='off']", visible: :all
    assert_selector "#playground-ir-inspector", text: /Lowering ready.*authoring nodes.*RenderIR nodes/, visible: :all

    authoring_ir = JSON.parse(page.find("#playground-authoring-ir", visible: :all).value)
    render_ir = JSON.parse(page.find("#playground-render-ir", visible: :all).value)
    assert_equal Showcase::Playground::IntermediateRepresentation::SCHEMA, authoring_ir.fetch("schema")
    assert_equal SwiftUIRails::RenderIR::SCHEMA, render_ir.fetch("schema")
    assert_equal "view", authoring_ir.dig("root", "type")
    assert_equal "fragment", render_ir.dig("root", "kind")
  end

  test "escapes hostile editor fixture diagnostic and IR content" do
    breakout = '</textarea><script id="payload-breakout">alert(1)</script><div>'
    source = <<~'RUBY'
      vstack do
        text("</textarea><script id=\"source-breakout\">alert(1)</script>")
      end
    RUBY
    data_json = JSON.generate(message: breakout)
    hostile_example = Showcase::Playground::Examples::Example.new(
      id: "hostile-fixture",
      name: '</a><script id="example-breakout">alert(1)</script><a>',
      description: '<img id="description-breakout" src=x onerror=alert(1)>',
      source: source,
      data_json: data_json
    )
    hostile_result = Showcase::Playground::Result.new(
      html: '<img id="result-breakout" src=x onerror=alert(1)>',
      diagnostics: [ { severity: "error", code: "fixture", message: breakout } ],
      stats: { source_bytes: source.bytesize },
      data: { "message" => breakout },
      render_ir: SwiftUIRails::RenderIR::Document.new(
        root: SwiftUIRails::RenderIR::Node.new(kind: "text", props: { content: breakout }),
        profile: "playground"
      )
    )

    render_inline(component(
      examples: [ hostile_example ],
      selected_example: hostile_example,
      initial_result: hostile_result,
      source: source,
      data_json: data_json
    ))

    %w[payload-breakout source-breakout example-breakout description-breakout result-breakout].each do |id|
      assert_no_selector "##{id}", visible: :all
    end
    assert_equal source, page.find("#playground-source", visible: :all).value
    assert_equal data_json, page.find("#playground-data", visible: :all).value
    # The escaped hostile diagnostic must still be shown to the user, not just
    # kept out of the DOM — proves diagnostics are rendered, not dropped.
    assert_selector "#playground-diagnostics-panel", text: breakout, visible: :all
    assert_equal breakout, JSON.parse(page.find("#playground-data-inspector", visible: :all).value).fetch("message")
    assert_equal breakout, JSON.parse(page.find("#playground-render-ir", visible: :all).value).dig("root", "props", "content")

    serialized = page.native.to_s
    refute_includes serialized, '</textarea><script id="source-breakout">'
    refute_includes serialized, '</textarea><script id="payload-breakout">'
  end

  test "requires owned examples and application-relative server endpoints" do
    other_example = Showcase::Playground::Examples.find("mission-readiness")
    assert_raises(ArgumentError) do
      render_inline(component(examples: [ @example ], selected_example: other_example))
    end
    assert_raises(TypeError) do
      render_inline(component(examples: [ "not an example" ]))
    end

    %i[
      compile_url run_url show_url preview_url assist_url language_url verify_url
      reliability_url
    ].each do |endpoint|
      [ "https://attacker.test/tool", "//attacker.test/tool", "/\\evil.test/tool", "/\tevil.test/tool" ].each do |unsafe_url|
        assert_raises(ArgumentError, "#{endpoint}: #{unsafe_url.inspect}") do
          render_inline(component(endpoint => unsafe_url))
        end
      end
    end
  end

  private

  def all_nodes(root)
    nodes = []
    pending = [ root ]
    until pending.empty?
      node = pending.pop
      nodes << node
      pending.concat(node.compact_child_nodes)
    end
    nodes
  end

  def component(
    examples: Showcase::Playground::Examples.all,
    selected_example: @example,
    initial_result: @result,
    compile_url: "/showcase/playground/compile",
    run_url: "/showcase/playground/run",
    show_url: "/showcase/playground",
    preview_url: "/showcase/playground/preview?example=product-catalog",
    source: nil,
    data_json: nil,
    assist_url: "/showcase/playground/assist",
    language_url: "/showcase/playground/language",
    verify_url: "/showcase/playground/verify",
    reliability_url: "/showcase/playground/reliability"
  )
    SwiftUiRailsPlaygroundComponent.new(
      examples: examples,
      selected_example: selected_example,
      initial_result: initial_result,
      compile_url: compile_url,
      run_url: run_url,
      show_url: show_url,
      preview_url: preview_url,
      source: source,
      data_json: data_json,
      assist_url: assist_url,
      language_url: language_url,
      verify_url: verify_url,
      reliability_url: reliability_url
    )
  end
end
