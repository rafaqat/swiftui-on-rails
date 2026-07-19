require "test_helper"

class RenderInDslTest < ActiveSupport::TestCase
  test "render embeds a ViewComponent inside a DSL element" do
    result = build_view.swift_ui do
      div do
        render ExampleComponent.new(title: "Nested component")
      end
    end

    fragment = Nokogiri::HTML.fragment(result)
    wrapper = fragment.at_css("div")

    assert_equal "Nested component", wrapper&.at_css("span.text-2xl.font-bold")&.text
    assert wrapper&.at_css("div.bg-white.rounded-lg.shadow-md.p-6")
    assert_equal 1, fragment.css("span").count { |node| node.text == "Nested component" }
  end

  test "DSL context render delegates to the view and returns safe HTML" do
    context = SwiftUIRails::DSLContext.new(build_view)
    result = context.render(ExampleComponent.new(title: "Delegated render"))

    assert_predicate result, :html_safe?
    assert_includes result, "Delegated render"
    assert_includes result, "bg-white rounded-lg shadow-md p-6"
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
