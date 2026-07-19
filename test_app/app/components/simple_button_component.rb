# frozen_string_literal: true

class SimpleButtonComponent < SwiftUIRails::Component::Base
  # ViewComponent 2.0 Collection Support
  prop :simple_button, type: Object, default: nil  # Required for with_collection
  prop :simple_button_counter, type: Integer, default: nil  # Counter variable access
  prop :collection_item, type: Object, default: nil  # For with_collection rendering
  prop :collection_counter, type: Integer, default: nil  # Counter variable access
  
  # Core props
  prop :title, type: String, required: false, default: "Button"
  prop :variant, type: Symbol, default: :primary
  prop :size, type: Symbol, default: :md
  prop :disabled, type: [TrueClass, FalseClass], default: false
  
  
  # SwiftUI-style customizable properties
  prop :background_color, type: String, default: nil
  prop :text_color, type: String, default: nil
  prop :corner_radius, type: String, default: "md"
  prop :padding_x, type: String, default: nil
  prop :padding_y, type: String, default: nil
  prop :font_weight, type: String, default: "medium"
  prop :font_size, type: String, default: nil
  
  # ViewComponent 2.0 Slot Support
  renders_one :icon, types: {
    system: "SystemIconComponent",
    custom: "CustomIconComponent"
  }
  renders_one :loading_state, "LoadingSpinnerComponent"
  
  VARIANT_CLASSES = {
    primary: { bg: "blue-600", hover_bg: "blue-700", text: "white" },
    secondary: { bg: "gray-200", hover_bg: "gray-300", text: "gray-900" },
    danger: { bg: "red-600", hover_bg: "red-700", text: "white" },
    success: { bg: "green-600", hover_bg: "green-700", text: "white" },
    warning: { bg: "yellow-500", hover_bg: "yellow-600", text: "white" }
  }.freeze
  
  SIZE_PRESETS = {
    sm: { px: "3", py: "2", text: "sm" },
    md: { px: "4", py: "2", text: "sm" },
    lg: { px: "6", py: "3", text: "base" },
    xl: { px: "8", py: "4", text: "lg" }
  }.freeze
  
  CORNER_RADIUS_OPTIONS = {
    none: "rounded-none",
    sm: "rounded-sm", 
    md: "rounded-md",
    lg: "rounded-lg",
    xl: "rounded-xl",
    full: "rounded-full"
  }.freeze
  
  # SECURITY: Add prop validations (must come after constants)
  validates_variant :variant, allowed: VARIANT_CLASSES.keys.map(&:to_s)
  validates_size :size, allowed: SIZE_PRESETS.keys.map(&:to_s)
  
  swift_ui do
    # Handle ViewComponent 2.0 collection rendering
    button_title = if simple_button
      simple_button.is_a?(Hash) ? simple_button[:title] || simple_button.to_s : simple_button.to_s
    elsif collection_item
      collection_item[:title] || collection_item.to_s
    else
      title
    end
    
    # Use collection counter from ViewComponent 2.0
    counter = simple_button_counter || collection_counter
    
    # Check if we have any ViewComponent 2.0 slots to render
    has_slots = icon? || loading_state? || counter
    
    if has_slots
      button(
        nil,  # No title when using block
        class: button_classes,
        disabled: disabled,
        style: inline_styles
      ) do
        # Include title in block content
        concat(button_title)
        
        # ViewComponent 2.0 slot composition
        if icon
          concat(icon.to_s)
        end
        
        if loading_state
          concat(loading_state.to_s)
        end
        
        # Collection counter badge if in collection
        if counter
          concat(content_tag(:span, " (#{counter + 1})", 
            class: "text-xs text-gray-400"))
        end
      end
    else
      # Simple button without slots
      button(
        button_title,
        class: button_classes,
        disabled: disabled,
        style: inline_styles,
        data: { component: "simple-button" }
      )
    end
  end
  
  # ViewComponent 2.0 Collection Optimization
  class << self
    def button_collection(buttons:, **options, &block)
      # Use ViewComponent 2.0 standard with_collection for 10x performance
      with_collection(buttons, **options)
    end
  end
  
  def button_classes
    # Use CSS class builder to avoid text-prefix conflicts
    CssClassBuilder.build do |builder|
      # Base classes
      builder.add("inline-flex items-center transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2")
      
      # Background and text colors (from variant or custom)
      if background_color.present? || text_color.present?
        # Custom colors override variant
        if background_color.blank?
          # Use variant background if no custom background
          variant_config = VARIANT_CLASSES[variant] || VARIANT_CLASSES[:primary]
          builder.add("bg-#{variant_config[:bg]} hover:bg-#{variant_config[:hover_bg]}")
        else
          # Apply custom background color
          # Ensure the full class name is generated for Tailwind to detect
          bg_class = "bg-#{background_color}"
          hover_class = "hover:bg-#{background_color}"
          builder.add("#{bg_class} #{hover_class} hover:brightness-90")
        end
        
        if text_color.present?
          builder.text_color(text_color)
        else
          # Smart default text color based on background
          if background_color.present?
            # Provide smart text color default for custom backgrounds
            if is_light_background?(background_color)
              builder.text_color("gray-900")  # Dark text on light background
            else
              builder.text_color("white")     # Light text on dark background
            end
          else
            # Use variant text color if no custom background
            variant_config = VARIANT_CLASSES[variant] || VARIANT_CLASSES[:primary]
            builder.text_color(variant_config[:text])
          end
        end
      else
        # Use variant preset
        variant_config = VARIANT_CLASSES[variant] || VARIANT_CLASSES[:primary]
        builder.add("bg-#{variant_config[:bg]} hover:bg-#{variant_config[:hover_bg]}")
        builder.add("focus:ring-#{variant_config[:bg].split('-').first}-500")
        builder.text_color(variant_config[:text])
      end
      
      # Corner radius
      radius_key = corner_radius.is_a?(String) ? corner_radius.to_sym : corner_radius
      builder.add(CORNER_RADIUS_OPTIONS[radius_key] || CORNER_RADIUS_OPTIONS[:md])
      
      # Size and padding
      if padding_x.present? || padding_y.present?
        # Custom padding
        builder.add("px-#{padding_x || '4'} py-#{padding_y || '2'}")
      else
        # Use size preset
        size_config = SIZE_PRESETS[size] || SIZE_PRESETS[:md]
        builder.add("px-#{size_config[:px]} py-#{size_config[:py]}")
      end
      
      # Font styling - apply font weight and size separately to avoid text- prefix conflicts
      builder.add("font-#{font_weight}")
      
      # Font size (will be applied before text color to avoid conflicts)
      if font_size.present?
        builder.text_size(font_size)
      else
        size_config = SIZE_PRESETS[size] || SIZE_PRESETS[:md]
        builder.text_size(size_config[:text])
      end
      
      # Disabled state
      builder.add("opacity-50 cursor-not-allowed") if disabled
    end
  end
  
  private
  
  def inline_styles
    styles = []
    
    if background_color.present?
      # Support hex colors, CSS color names, or Tailwind color references
      if background_color.start_with?('#')
        styles << "background-color: #{background_color}"
      elsif background_color.include?('-')
        # Tailwind color like "blue-500" - handled in CSS classes
      else
        styles << "background-color: #{background_color}"
      end
    end
    
    if text_color.present?
      if text_color.start_with?('#')
        styles << "color: #{text_color}"
      elsif text_color.include?('-')
        # Tailwind color - handled in CSS classes
      else
        styles << "color: #{text_color}"
      end
    end
    
    styles.empty? ? nil : styles.join("; ")
  end
  
  def is_light_background?(color)
    # Map of Tailwind color shades to determine if they're light or dark
    # Light colors (need dark text): 50, 100, 200, 300, 400
    # Dark colors (need light text): 500, 600, 700, 800, 900
    
    return false unless color.include?('-')
    
    # Extract shade number from Tailwind color (e.g., "blue-500" -> "500")
    shade = color.split('-').last.to_i
    
    # Colors 50-400 are generally light, 500-900 are dark
    shade <= 400
  end
end