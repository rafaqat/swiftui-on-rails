# frozen_string_literal: true

class DividerComponent < SwiftUIRails::Component::Base
  include SwiftUIRails::Security::ComponentValidator
  include SwiftUIRails::Security::CSSValidator
  
  VALID_ORIENTATIONS = %w[horizontal vertical].freeze
  VALID_THICKNESS = %w[1 2 4 8].freeze
  VALID_STYLES = %w[solid dashed dotted].freeze
  VALID_LENGTHS = %w[1/2 1/3 2/3 full].freeze
  
  prop :orientation, type: String, default: "horizontal"
  prop :thickness, type: String, default: "1"
  prop :color, type: String, default: "gray-200"
  prop :style, type: String, default: "solid"
  prop :length, type: String, default: ""
  
  # Add validations
  validates_inclusion :orientation, in: VALID_ORIENTATIONS
  validates_inclusion :thickness, in: VALID_THICKNESS
  validates_inclusion :style, in: VALID_STYLES
  validates_inclusion :length, in: VALID_LENGTHS + [""], allow_blank: true
  
  def before_render
    super
    # Validate color using CSS validator
    unless valid_tailwind_color?(color)
      raise ArgumentError, "Invalid color: #{color}. Must be a valid Tailwind color class."
    end
  end

  swift_ui do
    divider.tap do |d|
      if orientation == "vertical"
        d.border_l.border_t_0.h_full.w_0
      end
      
      case thickness
      when "2"
        d.border_2
      when "4"
        d.border_4
      when "8"
        d.border_8
      end
      
      d.border_color(color) if color != "gray-200"
      
      case style
      when "dashed"
        d.border_dashed
      when "dotted"
        d.border_dotted
      end
      
      case length
      when "1/2"
        d.w_1_2
      when "1/3"
        d.w_1_3
      when "2/3"
        d.w_2_3
      when "full"
        d.w_full
      end
    end
  end
  
  private
  
  def valid_tailwind_color?(color_class)
    return true if color_class.blank?
    
    # Extract color and shade
    parts = color_class.split("-")
    return false if parts.empty? || parts.size > 2
    
    color_name = parts[0]
    shade = parts[1]
    
    # Check if it's a valid color
    return true if %w[white black transparent current inherit].include?(color_name)
    
    # Check color with shade
    if shade
      VALID_COLORS.include?(color_name) && VALID_SHADES.include?(shade)
    else
      false
    end
  end
end