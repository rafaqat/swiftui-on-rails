# frozen_string_literal: true

class DslProductCardStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers
  
  # Define interactive controls
  control :product_name, as: :text, default: "Basic Tee"
  control :variant, as: :text, default: "Black"
  control :price, as: :number, default: 35
  control :currency, as: :select, options: ["$", "£", "€", "¥", "₹", "₪", "₩", "₽", "R$", "kr"], default: "$"
  control :image_url, as: :text, default: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg"
  control :show_hover, as: :boolean, default: true
  control :elevation, as: :select, options: [0, 1, 2, 3, 4], default: 2
  control :padding, as: :select, options: [4, 6, 8], default: 6
  control :background_color, as: :select, options: ["white", "gray-50", "gray-100"], default: "white"
  control :show_cta_button, as: :boolean, default: true
  control :cta_text, as: :text, default: "Add to bag"
  control :cta_style, as: :select, options: ["primary", "secondary", "outline"], default: "secondary"
  
  def default(product_name: "Basic Tee", variant: "Black", price: 35, currency: "$",
              image_url: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg",
              show_hover: true, elevation: 2, padding: 6, background_color: "white",
              show_cta_button: true, cta_text: "Add to bag", cta_style: "secondary")
    
    # Wrap in a container for better display
    content_tag(:div, class: "p-8 bg-gray-50 min-h-screen") do
      swift_ui do
        # Single product card using DSL chaining
        div(class: "max-w-sm mx-auto") do
          # Use the card DSL element with chained modifiers
          card(elevation: elevation) do
            # Product image container
            div.aspect("square").overflow("hidden").rounded("md").bg("gray-200") do
              img = image(
                src: image_url,
                alt: "#{product_name} in #{variant}"
              )
              # Apply hover effect using DSL chaining
              if show_hover
                img.w_full.h_full.object("cover").hover_scale(105).transition.duration(300)
              else
                img.w_full.h_full.object("cover")
              end
            end
            
            # Product details using DSL elements
            vstack(spacing: 2, alignment: :start) do
              text(product_name)
                .font_weight("semibold")
                .text_color("gray-900")
                .text_size("lg")
              
              text(variant)
                .text_color("gray-600")
                .text_size("sm")
              
              text("#{currency}#{price}")
                .font_weight("bold")
                .text_color("gray-900")
                .text_size("xl")
                .mt(2)
            end.mt(4)
            
            # CTA Button
            if show_cta_button
              button_classes = case cta_style
              when "primary"
                "w-full mt-4 px-4 py-2 bg-black text-white rounded-md hover:bg-gray-800 transition-colors"
              when "outline"
                "w-full mt-4 px-4 py-2 border-2 border-gray-900 text-gray-900 rounded-md hover:bg-gray-900 hover:text-white transition-colors"
              else # secondary
                "w-full mt-4 px-4 py-2 bg-gray-200 text-gray-900 rounded-md hover:bg-gray-300 transition-colors"
              end
              
              button(cta_text, class: button_classes)
                .font_weight("medium")
            end
          end
          .p(padding)
          .bg(background_color)
        end
      end
    end
  end
  
  # Multiple product cards in a grid
  def grid_layout(product_name: "Basic Tee", variant: "Black", price: 35, currency: "$",
                  image_url: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg",
                  show_hover: true, elevation: 2, padding: 6, background_color: "white",
                  show_cta_button: true, cta_text: "Add to bag", cta_style: "secondary")
    
    products = [
      { name: product_name, variant: variant, price: price, image: image_url },
      { name: "Comfort Hoodie", variant: "Gray", price: 89, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-01.jpg" },
      { name: "Summer Dress", variant: "Floral", price: 120, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-02.jpg" },
      { name: "Denim Jacket", variant: "Blue", price: 145, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-03.jpg" }
    ]
    
    content_tag(:div, class: "p-8 bg-gray-50 min-h-screen") do
      swift_ui do
        grid(columns: 2, spacing: 6) do
          products.each do |product|
            # Each product card using consistent DSL pattern
            card(elevation: elevation) do
              # Product image container
              div.aspect("square").overflow("hidden").rounded("md").bg("gray-200") do
                img = image(
                  src: product[:image],
                  alt: "#{product[:name]} in #{product[:variant]}"
                )
                if show_hover
                  img.w_full.h_full.object("cover").hover_scale(105).transition.duration(300)
                else
                  img.w_full.h_full.object("cover")
                end
              end
              
              # Product details
              vstack(spacing: 2, alignment: :start) do
                text(product[:name])
                  .font_weight("semibold")
                  .text_color("gray-900")
                  .text_size("lg")
                
                text(product[:variant])
                  .text_color("gray-600")
                  .text_size("sm")
                
                text("#{currency}#{product[:price]}")
                  .font_weight("bold")
                  .text_color("gray-900")
                  .text_size("xl")
                  .mt(2)
              end.mt(4)
              
              # CTA Button
              if show_cta_button
                button_classes = case cta_style
                when "primary"
                  "w-full mt-4 px-4 py-2 bg-black text-white rounded-md hover:bg-gray-800 transition-colors"
                when "outline"
                  "w-full mt-4 px-4 py-2 border-2 border-gray-900 text-gray-900 rounded-md hover:bg-gray-900 hover:text-white transition-colors"
                else # secondary
                  "w-full mt-4 px-4 py-2 bg-gray-200 text-gray-900 rounded-md hover:bg-gray-300 transition-colors"
                end
                
                button(cta_text, class: button_classes)
                  .font_weight("medium")
              end
            end
            .p(padding)
            .bg(background_color)
          end
        end.tw("md:grid-cols-4")
      end
    end
  end
  
  # Compact card variant
  def compact(product_name: "Basic Tee", variant: "Black", price: 35, currency: "$",
              image_url: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg",
              show_hover: true, elevation: 1, padding: 4, background_color: "white",
              show_cta_button: true, cta_text: "Add to bag", cta_style: "secondary")
    
    content_tag(:div, class: "p-8 bg-gray-50 min-h-screen") do
      swift_ui do
        div(class: "max-w-xs mx-auto") do
          # Compact card with less padding and smaller text
          card(elevation: elevation) do
            # Smaller image container
            div.aspect("square").overflow("hidden").rounded("md").bg("gray-200") do
              img = image(
                src: image_url,
                alt: "#{product_name} in #{variant}"
              )
              if show_hover
                img.w_full.h_full.object("cover").hover_scale(105).transition.duration(200)
              else
                img.w_full.h_full.object("cover")
              end
            end
            
            # Compact product details
            vstack(spacing: 1, alignment: :start) do
              text(product_name)
                .font_weight("medium")
                .text_color("gray-900")
                .text_size("base")
              
              text(variant)
                .text_color("gray-600")
                .text_size("xs")
              
              text("#{currency}#{price}")
                .font_weight("semibold")
                .text_color("gray-900")
                .text_size("lg")
                .mt(1)
            end.mt(3)
            
            # CTA Button (smaller for compact variant)
            if show_cta_button
              button_classes = case cta_style
              when "primary"
                "w-full mt-3 px-3 py-1.5 text-sm bg-black text-white rounded-md hover:bg-gray-800 transition-colors"
              when "outline"
                "w-full mt-3 px-3 py-1.5 text-sm border-2 border-gray-900 text-gray-900 rounded-md hover:bg-gray-900 hover:text-white transition-colors"
              else # secondary
                "w-full mt-3 px-3 py-1.5 text-sm bg-gray-200 text-gray-900 rounded-md hover:bg-gray-300 transition-colors"
              end
              
              button(cta_text, class: button_classes)
                .font_weight("medium")
            end
          end
          .p(padding)
          .bg(background_color)
        end
      end
    end
  end
end
