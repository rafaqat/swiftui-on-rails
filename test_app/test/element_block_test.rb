require "test_helper"
require "timeout"

class ElementBlockTest < ActiveSupport::TestCase
  test "element blocks capture multiple children exactly once" do
    context = SwiftUIRails::DSLContext.new(build_view)
    element = context.instance_eval do
      vstack do
        text("Line 1")
        text("Line 2")
      end
    end

    fragment = Nokogiri::HTML.fragment(element.to_s)

    assert_instance_of SwiftUIRails::DSL::Element, element
    assert_equal ["Line 1", "Line 2"], fragment.css("span").map(&:text)
    assert_equal 1, fragment.css("span").count { |node| node.text == "Line 1" }
    assert_equal 1, fragment.css("span").count { |node| node.text == "Line 2" }
  end

  test "array results of registered children are not stringified or duplicated" do
    context = SwiftUIRails::DSLContext.new(build_view)
    element = context.instance_eval do
      div do
        [text("First child"), text("Second child")]
      end
    end

    html = Timeout.timeout(2) { element.to_s }
    fragment = Nokogiri::HTML.fragment(html)

    assert_equal ["First child", "Second child"], fragment.css("span").map(&:text)
    refute_includes html, "#<SwiftUIRails::DSL::Element"
    refute_includes html, "#<SwiftUIRails::DSLContext"
  end

  test "arrays returned by enumerable composition do not leak domain objects" do
    context = SwiftUIRails::DSLContext.new(build_view)
    rows = [{ label: "Flight readiness", value: 75 }]
    element = context.instance_eval do
      div do
        rows.each { |row| text(row.fetch(:label)) }
      end
    end

    html = Timeout.timeout(2) { element.to_s }

    assert_includes html, "Flight readiness"
    refute_includes html, "{label:"
    refute_includes html, "value: 75"
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
  end
end
