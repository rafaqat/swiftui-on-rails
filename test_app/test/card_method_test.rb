require "test_helper"

class CardMethodTest < ActiveSupport::TestCase
  test "card modifiers preserve the element and attach a content block" do
    context = SwiftUIRails::DSLContext.new(build_view)
    card = context.card(elevation: 2)
    modified_card = card.p(6) { context.text("Inside card") }

    assert_instance_of SwiftUIRails::DSL::Element, card
    assert_same card, modified_card

    html = modified_card.to_s
    assert_includes html, "Inside card"
    assert_match(/class="[^"]*shadow-md[^"]*p-6/, html)
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
  end
end
