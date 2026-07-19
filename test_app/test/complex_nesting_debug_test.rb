require "test_helper"

class ComplexNestingDebugTest < ActiveSupport::TestCase
  test "complex nesting preserves hierarchy and renders each child once" do
    result = build_view.swift_ui do
      vstack(spacing: 24).p(8) do
        text("Header")
        card(elevation: 2).p(6) do
          text("Inside card")
        end
      end
    end

    fragment = Nokogiri::HTML.fragment(result)
    outer = fragment.at_css("div.flex.flex-col.p-8")
    card = outer&.at_css("div.bg-white.shadow-md.p-6")

    assert_equal "Header", outer&.at_xpath("./span")&.text
    assert_equal "Inside card", card&.at_xpath("./span")&.text
    assert_equal 1, fragment.css("span").count { |node| node.text == "Header" }
    assert_equal 1, fragment.css("span").count { |node| node.text == "Inside card" }
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
