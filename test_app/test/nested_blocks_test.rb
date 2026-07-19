require "test_helper"

class NestedBlocksTest < ActiveSupport::TestCase
  test "nested layout blocks render content at every level" do
    result = build_view.swift_ui do
      vstack do
        text("Level 1")
        card(elevation: 2) do
          text("Level 2")
          hstack do
            text("Level 3")
          end
        end
      end
    end

    fragment = Nokogiri::HTML.fragment(result)
    card = fragment.at_css("div.bg-white.shadow-md")

    assert_equal ["Level 1", "Level 2", "Level 3"], fragment.css("span").map(&:text)
    assert_equal "Level 3", card&.at_css("div.flex.flex-row span")&.text
    assert_equal 1, fragment.css("div.bg-white.shadow-md").size
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
