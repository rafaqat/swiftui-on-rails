# frozen_string_literal: true

module SwiftUIRails
  module Security
    # SECURITY: Validates CSS classes to prevent CSS injection attacks
    module CSSValidator
      # Allowed values for various CSS properties
      VALID_COLORS = %w[
        white black red blue green yellow gray purple pink orange indigo
        slate zinc neutral stone amber teal cyan sky violet fuchsia rose
        transparent current inherit
      ].freeze
      
      VALID_SHADES = %w[50 100 200 300 400 500 600 700 800 900 950].freeze
      
      VALID_ASPECTS = %w[
        auto square video wide 
        1/1 3/2 4/3 5/4 16/9 16/10 21/9
      ].freeze
      
      VALID_GRID_COLS = ((1..12).to_a + %w[none subgrid]).freeze
      
      VALID_SPACING = %w[
        0 px 0.5 1 1.5 2 2.5 3 3.5 4 5 6 7 8 9 10 11 12 
        14 16 20 24 28 32 36 40 44 48 52 56 60 64 72 80 96
        auto full 1/2 1/3 2/3 1/4 2/4 3/4
      ].freeze
      
      VALID_SHADOWS = %w[none sm md lg xl 2xl inner].freeze
      
      VALID_ROUNDED = %w[none sm md lg xl 2xl 3xl full].freeze

      # Edge/corner variants: rounded-l-md, rounded-tr-full, bare rounded-t.
      VALID_ROUNDED_WITH_EDGES = (
        VALID_ROUNDED +
        %w[t b l r tl tr bl br].flat_map do |edge|
          [edge] + VALID_ROUNDED.map { |size| "#{edge}-#{size}" }
        end
      ).freeze
      
      VALID_TEXT_SIZES = %w[xs sm base lg xl 2xl 3xl 4xl 5xl 6xl 7xl 8xl 9xl].freeze
      
      VALID_FONT_WEIGHTS = %w[thin extralight light normal medium semibold bold extrabold black].freeze
      
      VALID_TRANSITIONS = %w[none all colors opacity shadow transform].freeze
      
      VALID_DURATIONS = %w[75 100 150 200 300 500 700 1000].freeze
      
      VALID_SCALES = %w[0 50 75 90 95 100 105 110 125 150].freeze
      
      VALID_OPACITIES = %w[0 5 10 20 25 30 40 50 60 70 75 80 90 95 100].freeze
      
      # Pattern for valid CSS identifiers
      CSS_IDENTIFIER = /\A[a-zA-Z0-9\-_\/]+\z/
      
      class << self
        # Validate and return safe background color class
        def safe_bg_class(color, shade = nil)
          return "bg-gray-500" unless color
          
          color_str = color.to_s.downcase
          if VALID_COLORS.include?(color_str)
            if shade && VALID_SHADES.include?(shade.to_s)
              "bg-#{color_str}-#{shade}"
            elsif color_str == "transparent" || color_str == "current" || color_str == "inherit"
              "bg-#{color_str}"
            elsif color_str == "white" || color_str == "black"
              "bg-#{color_str}"
            else
              "bg-#{color_str}-500"
            end
          else
            "bg-gray-500"
          end
        end
        
        # Validate and return safe text color class
        def safe_text_class(color, shade = nil)
          return "text-gray-900" unless color
          
          color_str = color.to_s.downcase
          if VALID_COLORS.include?(color_str)
            if shade && VALID_SHADES.include?(shade.to_s)
              "text-#{color_str}-#{shade}"
            elsif color_str == "transparent" || color_str == "current" || color_str == "inherit"
              "text-#{color_str}"
            elsif color_str == "white" || color_str == "black"
              "text-#{color_str}"
            else
              "text-#{color_str}-900"
            end
          else
            "text-gray-900"
          end
        end
        
        # Validate and return safe aspect ratio class
        def safe_aspect_class(ratio)
          return "aspect-square" unless ratio
          
          ratio_str = ratio.to_s
          if VALID_ASPECTS.include?(ratio_str)
            "aspect-#{ratio_str.gsub('/', '-')}"
          else
            "aspect-square"
          end
        end
        
        # Validate and return safe grid columns class
        def safe_grid_cols_class(cols)
          return "grid-cols-1" unless cols
          
          cols_value = cols.to_s
          # Guard the interpolated value itself: String#to_i parses only leading
          # digits, so "1alert(1)" would otherwise pass the numeric check and be
          # interpolated verbatim. Only accept an exact allowlist match or a
          # fully-numeric string whose integer value is allowlisted.
          if VALID_GRID_COLS.include?(cols_value) ||
             (cols_value.match?(/\A\d+\z/) && VALID_GRID_COLS.include?(cols_value.to_i))
            "grid-cols-#{cols_value}"
          else
            "grid-cols-1"
          end
        end
        
        # Validate and return safe spacing class
        def safe_spacing_class(prefix, value)
          return "#{prefix}-0" unless value && %w[p m px py mx my pt pb pl pr mt mb ml mr].include?(prefix)
          
          value_str = value.to_s
          if VALID_SPACING.include?(value_str)
            "#{prefix}-#{value_str.gsub('/', '-')}"
          else
            "#{prefix}-0"
          end
        end
        
        # Validate and return safe shadow class
        def safe_shadow_class(size)
          return "shadow" unless size
          
          size_str = size.to_s
          if VALID_SHADOWS.include?(size_str)
            size_str == "none" ? "shadow-none" : "shadow-#{size_str}"
          else
            "shadow"
          end
        end
        
        # Validate and return safe rounded class
        def safe_rounded_class(size)
          return "rounded" unless size
          
          size_str = size.to_s
          if VALID_ROUNDED.include?(size_str)
            size_str == "none" ? "rounded-none" : "rounded-#{size_str}"
          else
            "rounded"
          end
        end
        
        # Validate and return safe text size class
        def safe_text_size_class(size)
          return "text-base" unless size
          
          size_str = size.to_s
          if VALID_TEXT_SIZES.include?(size_str)
            "text-#{size_str}"
          else
            "text-base"
          end
        end
        
        # Validate and return safe font weight class
        def safe_font_weight_class(weight)
          return "font-normal" unless weight
          
          weight_str = weight.to_s
          if VALID_FONT_WEIGHTS.include?(weight_str)
            "font-#{weight_str}"
          else
            "font-normal"
          end
        end
        
        # Validate any generic CSS value
        def valid_css_value?(value)
          return false unless value
          
          value.to_s.match?(CSS_IDENTIFIER)
        end
        
        # Sanitize any CSS value to prevent injection
        def sanitize_css_value(value)
          return "" unless value
          
          # Remove any potentially dangerous characters
          value.to_s.gsub(/[^a-zA-Z0-9\-_\/]/, '')
        end
        
        # Check if a complete CSS class is safe
        def safe_css_class?(css_class)
          return false unless css_class
          
          # Check for common injection patterns
          return false if css_class.include?(';') || css_class.include?('{') || css_class.include?('}')
          return false if css_class.include?('<') || css_class.include?('>')
          return false if css_class.include?('javascript:') || css_class.include?('data:')
          
          # Must match valid CSS class pattern
          css_class.match?(/\A[a-zA-Z0-9\-_:\/\s]+\z/)
        end
        
        # Build a safe CSS class string from components
        def build_safe_class(prefix, value, fallback = nil)
          return fallback unless prefix && value
          
          sanitized_prefix = sanitize_css_value(prefix)
          sanitized_value = sanitize_css_value(value)
          
          return fallback if sanitized_prefix.empty? || sanitized_value.empty?
          
          "#{sanitized_prefix}-#{sanitized_value}"
        end
      end
    end
  end
end