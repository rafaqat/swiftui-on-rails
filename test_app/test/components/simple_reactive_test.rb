# frozen_string_literal: true

require "test_helper"

class SimpleReactiveTest < ViewComponent::TestCase
  class SimpleComponent < SwiftUIRails::Component::Base
    prop :title, type: String, default: "Hello"
    
    swift_ui do
      text(title)
    end
  end
  
  def test_simple_component_renders
    render_inline(SimpleComponent.new(title: "Test"))
    assert_text "Test"
  end
end
