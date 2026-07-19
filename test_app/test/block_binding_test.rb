require "test_helper"

class BlockBindingTest < ActiveSupport::TestCase
  test "modifier chains retain a trailing content block" do
    result = build_view.swift_ui do
      vstack(spacing: 24).p(8).mx("auto") do
        text("Bound content")
      end
    end

    assert_predicate result, :html_safe?
    assert_includes result, "Bound content"
    assert_match(/class="[^"]*p-8[^"]*mx-auto/, result)
    assert_includes result, 'style="gap: 24px"'
  end

  test "modifiers chained after a nested block preserve all content" do
    result = build_view.swift_ui do
      vstack(spacing: 24) do
        text("Header")
        card(elevation: 2) do
          vstack(spacing: 16) do
            text("Inside nested vstack")
            button("Button 1")
          end
        end.p(6)
      end.p(8).max_w("4xl").mx("auto")
    end

    assert_includes result, "Header"
    assert_includes result, "Inside nested vstack"
    assert_includes result, "Button 1"
    assert_match(/class="[^"]*p-8[^"]*max-w-4xl[^"]*mx-auto/, result)
  end

  test "Ruby actions compile to opaque framework-neutral capabilities" do
    result = build_view.swift_ui do
      card = div do
        text("Interactive Card")
      end
      card.on_click { nil }
    end

    fragment = Nokogiri::HTML.fragment(result)
    interactive_card = fragment.at_css("[data-sui-actions]")

    assert interactive_card, "Expected the semantic action element to render"
    assert_equal "Interactive Card", interactive_card.text
    action_id = JSON.parse(interactive_card["data-sui-actions"]).fetch("click")
    assert_match(/\Aa_[0-9a-f]{32}\z/, action_id)
    refute_match(/controller|#/, action_id)
  end

  test "legacy controller target and param modifiers are deterministically rejected" do
    legacy_calls = {
      stimulus_controller: ["cart"],
      stimulus_target: ["submitButton"],
      stimulus_param: ["product-id", 42],
      stimulus_action: ["click->cart#add"]
    }
    legacy_calls.each do |method, arguments|
      error = assert_raises(SwiftUIRails::Error, method.to_s) do
        build_view.swift_ui do
          button("Add to cart").public_send(method, *arguments)
        end
      end

      assert_match(/Application JavaScript|unsupported/i, error.message)
    end
  end

  test "raw application callback metadata is rejected at the IR boundary" do
    error = assert_raises(SwiftUIRails::RenderIR::InvalidStructure) do
      build_view.swift_ui do
        button("Unsafe", data: { action: "click->cart#add eval->malicious#code" })
      end
    end

    assert_match(/Application JavaScript metadata/, error.message)
  end

  test "links reject executable URL schemes" do
    result = build_view.swift_ui do
      vstack do
        link("Unsafe", destination: "javascript:alert('xss')")
        link("Safe", destination: "https://example.com/docs")
      end
    end

    fragment = Nokogiri::HTML.fragment(result)

    links = fragment.css("a")
    assert_equal "#", links[0]["href"]
    assert_equal "https://example.com/docs", links[1]["href"]
  end

  test "elements created outside a DSL context escape ordinary block strings" do
    view = build_view
    element = SwiftUIRails::DSL::Element.new(:div) do
      '<img id="outside-context-xss" src="x" onerror="alert(1)">'
    end
    element.view_context = view

    fragment = Nokogiri::HTML.fragment(element.to_s)

    refute fragment.at_css("#outside-context-xss")
    assert_includes fragment.text, '<img id="outside-context-xss"'
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
