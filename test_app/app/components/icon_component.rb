# frozen_string_literal: true

class IconComponent < SwiftUIRails::Component::Base
  # Type alias for better readability
  Boolean = [TrueClass, FalseClass].freeze
  
  prop :name, type: String, default: "star"
  prop :size, type: Integer, default: 24
  prop :color, type: String, default: "gray-500"
  prop :stroke_width, type: Float, default: 2.0
  prop :filled, type: Boolean, default: false

  swift_ui do
    icon(name, size: size).tap do |element|
      element.text_color(color) if color != "gray-500"
      element.stroke_width(stroke_width) if stroke_width != 2.0
      element.filled if filled
    end
  end
end