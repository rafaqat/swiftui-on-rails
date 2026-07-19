# frozen_string_literal: true

require "test_helper"

class MinimalTest < ViewComponent::TestCase
  # Test without any reactive features
  class MinimalComponent < ViewComponent::Base
    def call
      content_tag(:div, "Hello World")
    end
  end
  
  # Test with Base class but no reactive
  class BaseComponent < SwiftUIRails::Component::Base
    def call
      content_tag(:div, "Base Component")
    end
  end
  
  # Test with swift_ui block
  class SwiftUIComponent < SwiftUIRails::Component::Base
    swift_ui do
      text("Swift UI Component")
    end
  end
  
  def test_minimal_component
    render_inline(MinimalComponent.new)
    assert_text "Hello World"
  end
  
  def test_base_component
    render_inline(BaseComponent.new)
    assert_text "Base Component"
  end
  
  def test_swift_ui_component
    render_inline(SwiftUIComponent.new)
    assert_text "Swift UI Component"
  end
end
