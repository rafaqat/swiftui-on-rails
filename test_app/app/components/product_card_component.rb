# frozen_string_literal: true

class ProductCardComponent < ApplicationComponent
  include SwiftUIRails::Helpers
  include SwiftUIRails::Security::ComponentValidator
  
  VALID_ASPECT_RATIOS = %w[square auto 1/1 3/2 4/3 5/4 16/9 16/10 21/9].freeze
  
  # Product data
  prop :product, type: Hash, required: true
  prop :index, type: Integer, default: 0
  
  # Display options
  prop :card_style, type: Symbol, default: :standard
  prop :show_variants, type: [TrueClass, FalseClass], default: true
  prop :show_quick_actions, type: [TrueClass, FalseClass], default: true
  prop :image_aspect_ratio, type: String, default: "square"
  
  # Add validation
  validates_inclusion :image_aspect_ratio, in: VALID_ASPECT_RATIOS
  
  # Action handlers
  prop :on_click, type: Proc, default: nil
  prop :on_add_to_cart, type: Proc, default: nil
  prop :on_variant_select, type: Proc, default: nil
  prop :on_quick_view, type: Proc, default: nil
  
  # Validate callable props
  validates_callable :on_click
  validates_callable :on_add_to_cart
  validates_callable :on_variant_select
  validates_callable :on_quick_view
  
  swift_ui do
    div do
      # Product Image with overlay actions
      div.relative do
        # Render product image or placeholder
        render_product_image
        
        # Out of stock badge
        if product[:in_stock] == false
          div do
            text("Out of Stock")
          end
          .absolute
          .top(2)
          .right(2)
          .bg("red-600")
          .text_color("white")
          .px(3)
          .py(1)
          .rounded("full")
          .text_size("xs")
          .font_weight("semibold")
        end
        
        # Sale badge
        if product[:on_sale]
          div do
            text("Sale")
          end
          .absolute
          .top(2)
          .left(2)
          .bg("green-600")
          .text_color("white")
          .px(3)
          .py(1)
          .rounded("full")
          .text_size("xs")
          .font_weight("semibold")
        end
      end
      
      # Product details
      div.mt(4) do
        hstack.justify_between.items_start do
          # Product info
          vstack(alignment: :leading, spacing: 1).flex_1 do
            # Product name
            text(product[:name])
              .text_size("sm")
              .text_color("gray-700")
              .font_weight("medium")
              .line_clamp(2)
            
            # Product variant/description
            if product[:variant_label].present?
              text(product[:variant_label])
                .text_size("sm")
                .text_color("gray-500")
            end
          end
          
          # Price
          vstack(alignment: :trailing, spacing: 1) do
            # Current price
            text("#{product[:currency] || '$'}#{product[:price]}")
              .text_size("sm")
              .font_weight("semibold")
              .text_color("gray-900")
            
            # Original price (if on sale)
            if product[:original_price] && product[:original_price] > product[:price]
              text("#{product[:currency] || '$'}#{product[:original_price]}")
                .text_size("xs")
                .text_color("gray-500")
                .line_through
            end
          end
        end
        
        # Additional info (ratings, etc)
        if product[:rating] || product[:reviews_count]
          hstack(spacing: 2).mt(2) do
            if product[:rating]
              # Simple star rating
              hstack(spacing: 0.5) do
                (1..5).each do |star|
                  if star <= product[:rating].to_i
                    text("★").text_color("yellow-400").text_size("xs")
                  else
                    text("☆").text_color("gray-300").text_size("xs")
                  end
                end
              end
            end
            
            if product[:reviews_count]
              text("(#{product[:reviews_count]})")
                .text_size("xs")
                .text_color("gray-500")
            end
          end
        end
      end
    end
    .group
    .relative
    .data(
      "product-id": product[:id] || "unknown",
      "product-index": index
    )
  end
  
  private
  
  def render_product_image
    if product[:image_url].present?
      img = image(src: product[:image_url], alt: product[:name])
        .w("full")
        .rounded("md")
        .bg("gray-200")
        .object("cover")
        .group_hover("opacity-75")
      
      apply_aspect_ratio(img)
    else
      render_image_placeholder
    end
  end
  
  def render_image_placeholder
    placeholder = div do
      text("No Image")
        .text_color("gray-400")
        .text_size("sm")
    end
    .w("full")
    .rounded("md")
    .bg("gray-200")
    .flex
    .items_center
    .justify_center
    
    apply_aspect_ratio(placeholder)
  end
  
  def apply_aspect_ratio(element)
    case image_aspect_ratio
    when "square"
      element.aspect("square")
    when "auto"
      element.aspect("auto").lg("h-80")
    else
      element.aspect(image_aspect_ratio)
    end
  end
end