# frozen_string_literal: true

class ProductRatingComponent < SwiftUIRails::Component::Base
  include SwiftUIRails::Security::ComponentValidator
  
  prop :rating, type: [Integer, Float], required: true
  prop :max_rating, type: Integer, default: 5
  prop :size, type: Symbol, default: :sm, enum: [:xs, :sm, :md, :lg]
  prop :show_text, type: [TrueClass, FalseClass], default: false
  prop :interactive, type: [TrueClass, FalseClass], default: false
  prop :on_rate, type: Proc, default: nil

  state :current_rating, -> { rating }, type: [Integer, Float]
  
  # Add validation for rating range
  validates_number :rating, min: 0
  validates_number :max_rating, min: 1, max: 10
  
  def before_render
    super
    # Additional runtime validation
    if rating > max_rating
      raise ArgumentError, "Rating (#{rating}) cannot exceed max_rating (#{max_rating})"
    end
  end
  
  swift_ui do
    hstack(spacing: 0.5).items_center do
      # Star icons
      (1..max_rating).each do |star|
        star_button = button(type: "button", disabled: !interactive) do
          if star <= current_rating.floor
            # Full star
            span
              .text_color(interactive ? "yellow-400" : "yellow-500")
              .text_size(star_text_size) do
              text("★")
            end
          elsif star == current_rating.ceil && current_rating % 1 != 0
            # Half star - for simplicity, show as full star with different opacity
            span
              .text_color(interactive ? "yellow-400" : "yellow-500")
              .tw("opacity-70")
              .text_size(star_text_size) do
              text("★")
            end
          else
            # Empty star
            span
              .text_color("gray-300")
              .text_size(star_text_size) do
              text("☆")
            end
          end
        end

        star_button
          .p(0)
          .cursor(interactive ? "pointer" : "default")
          .attr("aria-label", "Rate #{star} out of #{max_rating} stars")

        if interactive
          star_button.data(star_rating: star)
          star_button.on_click do
            self.current_rating = star
            on_rate.call(star) if on_rate.respond_to?(:call)
          end
        end
      end
      
      # Rating text
      if show_text
        text("#{current_rating.round(1)}")
          .text_size(text_size)
          .text_color("gray-600")
          .ml(2)
      end
    end
  end
  
  def star_size
    @star_size ||= case size
    when :xs then 3
    when :sm then 4
    when :md then 5
    when :lg then 6
    else 4
    end
  end
  
  def star_text_size
    @star_text_size ||= case size
    when :xs then "xs"
    when :sm then "sm"
    when :md then "lg"
    when :lg then "xl"
    else "sm"
    end
  end
  
  def text_size
    @text_size ||= case size
    when :xs then "xs"
    when :sm then "sm"
    when :md then "base"
    when :lg then "lg"
    else "sm"
    end
  end
end
