require "test_helper"

class ChainedBlocksTest < ActiveSupport::TestCase
  test "nested modifier chains render their blocks and styles" do
    result = build_view.swift_ui do
      vstack(spacing: 24).p(8).max_w("4xl").mx("auto") do
        text("Header")
        card(elevation: 2).p(6) do
          hstack(spacing: 12) do
            button("Button 1")
            button("Button 2")
          end
        end
      end
    end

    fragment = Nokogiri::HTML.fragment(result)
    outer = fragment.at_css("div.flex.flex-col.p-8.max-w-4xl.mx-auto")
    card = outer&.at_css("div.bg-white.rounded-lg.shadow-md.p-6")

    assert outer, "Expected the outer modifier chain to render"
    assert card, "Expected the chained card to render"
    assert_equal ["Button 1", "Button 2"], card.css("button").map(&:text)
    assert_equal 1, fragment.css("span").count { |node| node.text == "Header" }
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
