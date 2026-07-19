# frozen_string_literal: true

require "test_helper"

class SwiftUIRails::RenderIRRuntimeTest < ViewComponent::TestCase
  class RuntimeComponent < SwiftUIRails::Component::Base
    swift_ui do
      vstack(alignment: :leading, spacing: 12) do
        text("Status").text_style(:supporting)
        button("Inspect").button_style(:bordered)
      end
    end
  end

  class ReactiveRuntimeComponent < SwiftUIRails::Component::Base
    class_attribute :render_executions, default: 0

    state :count, 0, type: Integer

    swift_ui do
      record_render_execution
      vstack { text("Count: #{count}") }
    end

    private

    def record_render_execution
      self.class.render_executions += 1
    end
  end

  test "the live component path lowers once to semantic RenderIR before HTML" do
    component = RuntimeComponent.new
    render_inline(component)

    document = component.last_render_ir
    assert_instance_of SwiftUIRails::RenderIR::Document, document
    assert_equal "fragment", document.root.kind
    assert_equal %w[fragment vstack text text_literal button text_literal], document.each_node.map(&:kind)
    assert_equal [ "text_style" ], document.each_node.find { |node| node.kind == "text" }.modifiers.map(&:name)
    assert_equal [ "button_style" ], document.each_node.find { |node| node.kind == "button" }.modifiers.map(&:name)
    assert_equal document, SwiftUIRails::RenderIR::Document.from_json(document.canonical_json)
    assert_text "Status"
    assert_button "Inspect"
  end

  test "a DSL block executes exactly once during lowering" do
    executions = 0
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval do
      vstack do
        executions += 1
        text("One pass")
      end
    end

    html = context.flush_elements

    assert_equal 1, executions
    assert_includes html, "One pass"
    assert_instance_of SwiftUIRails::RenderIR::Document, context.last_render_ir
  end

  test "reactive components record their complete outer container in one RenderIR pass" do
    ReactiveRuntimeComponent.render_executions = 0
    component = ReactiveRuntimeComponent.new

    render_inline(component)

    document = component.last_render_ir
    wrapper = document.root.children.fetch(0)
    attributes = wrapper.props.fetch("attribute_pairs").to_h

    assert_equal 1, ReactiveRuntimeComponent.render_executions
    assert_equal %w[fragment reactive_container vstack text text_literal], document.each_node.map(&:kind)
    assert_equal "reactive_container", wrapper.kind
    assert_equal "div", wrapper.props.fetch("tag")
    assert_equal component.component_id, wrapper.identity
    assert_equal component.component_id, attributes.fetch("id")
    assert_equal "1", attributes.fetch("data-sui-root")
    assert_equal component.component_id, attributes.fetch("data-sui-id")
    assert_equal component.class.name, attributes.fetch("data-sui-component")
    assert attributes.fetch("data-sui-stream").present?
    assert attributes.fetch("data-sui-snapshot").present?
    refute attributes.key?("data-controller")
    refute attributes.key?("data-action")
    refute document.each_node.any? { |node| node.kind == "trusted_html" }
    assert_selector "##{component.component_id}[data-sui-root='1']", text: "Count: 0"
  end

  test "trusted HTML is opaque request-local capability data" do
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval do
      vstack { "<strong>Trusted child</strong>".html_safe }
    end

    html = context.flush_elements
    document = context.last_render_ir
    trusted = document.each_node.find { |node| node.kind == "trusted_html" }

    assert_includes html, "<strong>Trusted child</strong>"
    assert trusted
    assert_match(/\Atrusted_html:[a-f0-9]{24}:\d+\z/, trusted.props.fetch("capability"))
    refute_includes document.canonical_json, "<strong>"
    assert_equal 1, document.metadata.fetch("capability_count")
  end

  test "ordinary strings remain escaped through the IR renderer" do
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval { text("<script>alert(1)</script>") }

    html = context.flush_elements

    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes html, "<script>"
  end

  test "IR validation rejects inline JavaScript attributes" do
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval { div.attr(:onclick, "alert(1)") }

    error = assert_raises(SwiftUIRails::RenderIR::InvalidStructure) do
      context.flush_elements
    end

    assert_equal "$.root.children[0].props.attribute_pairs[0][0]", error.path
    assert_match(/invalid or unsafe/, error.message)
  end

  test "environment values remain private while the modifier keeps semantic keys" do
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval do
      div("Private context").environment(api_token: "do-not-serialize")
    end

    context.flush_elements
    document = context.last_render_ir
    environment_modifier = document.each_node.flat_map(&:modifiers).find do |modifier|
      modifier.name == "environment"
    end

    assert environment_modifier
    assert_equal [ "api_token" ], environment_modifier.keywords.fetch("keys")
    refute_includes document.canonical_json, "do-not-serialize"
  end

  test "IR validation rejects duplicate case-insensitive attributes" do
    context = SwiftUIRails::DSLContext.new(render_view)
    context.instance_eval { div(class: "first").attr("CLASS", "second") }

    error = assert_raises(SwiftUIRails::RenderIR::InvalidStructure) do
      context.flush_elements
    end

    assert_match(/duplicate attribute `class`/, error.message)
  end

  test "scoped identities are stable per root and preserve explicit IDs" do
    render_scope = lambda do
      context = SwiftUIRails::DSLContext.new(render_view)
      context.with_render_identity_scope("catalog:string:keyboard") do
        context.text("Generated text")
        context.article("Generated card")
        context.text("Explicit").id("author-id")
      end

      [ context.flush_elements, context.last_render_ir ]
    end

    first_html, first_document = render_scope.call
    second_html, second_document = render_scope.call
    first_roots = first_document.root.children
    second_roots = second_document.root.children

    assert_equal first_roots.map(&:identity), second_roots.map(&:identity)
    explicit_root = first_roots.find { |node| node.identity == "author-id" }
    generated_roots = first_roots.reject { |node| node.equal?(explicit_root) }

    assert explicit_root
    assert_match(/\Aswift-ui-ir-[0-9a-f]{32}\z/, first_roots.first.identity)
    assert_match(/\Aswift-ui-ir-[0-9a-f]{32}\z/, first_roots.second.identity)
    assert_equal 2, generated_roots.map(&:identity).uniq.length
    assert_includes first_html, %(data-morph-id="#{first_roots.first.identity}")
    assert_includes first_html, %(id="#{first_roots.first.identity}")
    assert_includes second_html, %(data-morph-id="#{second_roots.second.identity}")
    assert_includes first_html, %(id="author-id")
    refute_includes first_html, %(data-morph-id="author-id")
  end

  private

  def render_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
