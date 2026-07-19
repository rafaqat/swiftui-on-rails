# frozen_string_literal: true

require 'swift_ui_rails/security/url_validator'

class ImageComponent < SwiftUIRails::Component::Base
  prop :src, type: String, required: true, validate: :url
  prop :alt_text, type: String, default: "Image"
  prop :aspect_ratio, type: String, default: "square", enum: ["square", "portrait", "landscape", "wide"]
  prop :object_fit, type: String, default: "cover", enum: ["cover", "contain", "fill", "none", "scale-down"]
  prop :corner_radius, type: String, default: "none", enum: ["none", "sm", "md", "lg", "xl", "full"]
  prop :border, type: [TrueClass, FalseClass], default: false
  prop :grayscale, type: [TrueClass, FalseClass], default: false
  prop :blur, type: [TrueClass, FalseClass], default: false

  swift_ui do
    # SECURITY: Validate image source URL
    safe_src = SwiftUIRails::Security::URLValidator.validate_image_src(
      src,
      fallback: '/images/placeholder.png'
    )
    
    image(safe_src || '/images/placeholder.png', alt: alt_text).tap do |img|
      case aspect_ratio
      when "square"
        img.aspect_ratio("square")
      when "portrait"
        img.aspect_ratio("3/4")
      when "landscape"
        img.aspect_ratio("4/3")
      when "wide"
        img.aspect_ratio("16/9")
      end
      
      img.object_fit(object_fit) if object_fit != "cover"
      img.corner_radius(corner_radius) if corner_radius != "none"
      img.border if border
      img.grayscale if grayscale
      img.blur if blur
    end
  end
end