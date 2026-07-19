# frozen_string_literal: true

require "test_helper"

class ElementDebugTest < ViewComponent::TestCase
  # Super simple component
  class TextOnlyComponent < SwiftUIRails::Component::Base
    swift_ui do
      text("Hello World")
    end
  end
  
  # Component with vstack
  class VStackComponent < SwiftUIRails::Component::Base
    swift_ui do
      vstack do
        text("Inside vstack")
      end
    end
  end
  
  def test_text_only_component
    render_inline(TextOnlyComponent.new)
    assert_text "Hello World"
  end
  
  def test_vstack_component
    render_inline(VStackComponent.new)
    assert_text "Inside vstack"
  end
  
  def test_manual_element_rendering
    element = SwiftUIRails::DSL::Element.new(:span, "Hello Element")
    element.view_context = vc_test_controller.view_context
    html = element.to_s

    assert_equal "span", element.tag_name.to_s
    assert_includes html, "Hello Element"
  end
end
