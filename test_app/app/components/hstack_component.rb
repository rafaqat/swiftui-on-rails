# frozen_string_literal: true

class HstackComponent < SwiftUIRails::Component::Base
  # Props for layout configuration
  prop :spacing, type: Integer, default: 8
  prop :alignment, type: Symbol, default: :center
  prop :background_color, type: String, default: ""
  prop :padding, type: String, default: ""
  
  # Props for content configuration
  prop :first_button_text, type: String, default: "First"
  prop :first_button_style, type: Symbol, default: :primary
  prop :first_button_size, type: Symbol, default: :sm
  
  prop :middle_text, type: String, default: "Middle Text"
  prop :middle_text_weight, type: String, default: "medium"
  
  prop :last_button_text, type: String, default: "Last"
  prop :last_button_style, type: Symbol, default: :secondary
  prop :last_button_size, type: Symbol, default: :sm

  swift_ui do
    hstack(spacing: spacing, alignment: alignment) do
      button(first_button_text)
        .button_style(first_button_style)
        .button_size(first_button_size)
      
      text(middle_text)
        .font_weight(middle_text_weight)
      
      button(last_button_text)
        .button_style(last_button_style)
        .button_size(last_button_size)
    end.tap do |stack|
      stack.background(background_color) if background_color.present?
      stack.padding(padding) if padding.present?
    end
  end
end