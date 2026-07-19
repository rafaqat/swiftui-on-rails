# frozen_string_literal: true

class ProductLayoutSimpleStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::Helpers
  include SwiftUIRails::DSL
  
  # Pure DSL story - no backing component instantiation
  def default
    products = [
      { name: "Basic Tee", variant: "Black", price: 35, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg" },
      { name: "Basic Tee", variant: "White", price: 35, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-01.jpg" },
      { name: "Nomad Tumbler", variant: "White", price: 35, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-02.jpg" },
      { name: "Travel Mug", variant: "Black", price: 25, image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-03.jpg" }
    ]
    
    swift_ui do
      section.bg("gray-50").min_h("screen") do
        div.max_w("7xl").mx("auto").px(4).py(8).add_class("sm:px-6 lg:px-8") do
          # Header
          hstack(alignment: :center).mb(8) do
            vstack(alignment: :start, spacing: 2) do
              text("Product Catalog")
                .text_size("3xl")
                .font_weight("bold")
                .text_color("gray-900")
              
              text("#{products.count} items")
                .text_size("base")
                .text_color("gray-600")
            end
            spacer
          end
          
          # Product grid using DSL
          grid(columns: 2, spacing: 6) do
            products.each do |product|
              dsl_product_card(
                name: product[:name],
                price: product[:price],
                image_url: product[:image],
                variant: product[:variant],
                currency: "$",
                show_cta: true,
                cta_text: "Add to Cart",
                cta_style: "primary"
              )
            end
          end
        end
      end
    end
  end
  
  def with_filters
    products = generate_sample_products
    
    swift_ui do
      section.bg("gray-50").min_h("screen") do
        div.max_w("7xl").mx("auto").px(4).py(8).add_class("sm:px-6 lg:px-8") do
          # Header
          hstack(alignment: :center).mb(8) do
            vstack(alignment: :start, spacing: 2) do
              text("Filtered Products")
                .text_size("3xl")
                .font_weight("bold")
                .text_color("gray-900")
              
              text("#{products.count} items")
                .text_size("base")
                .text_color("gray-600")
            end
            spacer
          end
          
          # Filter section
          div.bg("white").p(6).rounded("lg").shadow("sm").border.border_color("gray-200").mb(6) do
            hstack(spacing: 4) do
              text("Filter by:").font_weight("medium")
              button("All").px(3).py(1).bg("blue-500").text_color("white").rounded("md")
              button("Shirts").px(3).py(1).bg("gray-200").text_color("gray-700").rounded("md")
              button("Accessories").px(3).py(1).bg("gray-200").text_color("gray-700").rounded("md")
              button("Outerwear").px(3).py(1).bg("gray-200").text_color("gray-700").rounded("md")
            end
          end
          
          # Product grid using DSL
          grid(columns: 3, spacing: 6) do
            products.each do |product|
              dsl_product_card(
                name: product[:name],
                price: product[:price],
                image_url: product[:image],
                variant: product[:variant],
                currency: "$",
                show_cta: true,
                cta_text: "Add to Cart",
                cta_style: "primary"
              )
            end
          end
        end
      end
    end
  end
  
  def four_column_grid
    products = generate_sample_products
    
    swift_ui do
      section.bg("gray-50").min_h("screen") do
        div.max_w("7xl").mx("auto").px(4).py(8).add_class("sm:px-6 lg:px-8") do
          # Header with sort dropdown
          hstack(alignment: :center).mb(8) do
            vstack(alignment: :start, spacing: 2) do
              text("Four Column Layout")
                .text_size("3xl")
                .font_weight("bold")
                .text_color("gray-900")
              
              text("#{products.count} items")
                .text_size("base")
                .text_color("gray-600")
            end
            
            spacer
            
            # Sort dropdown
            div.relative do
              select
                .block.w("full").pl(3).pr(10).py(2)
                .text_size("base").border("gray-300").rounded("md")
                .add_class("focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm") do
                option("popular", "Most Popular")
                option("newest", "Newest")
                option("price_asc", "Price: Low to High")
                option("price_desc", "Price: High to Low")
              end
            end
          end
          
          # Product grid using DSL - 4 columns
          grid(columns: 4, spacing: 6) do
            products.each do |product|
              dsl_product_card(
                name: product[:name],
                price: product[:price],
                image_url: product[:image],
                variant: product[:variant],
                currency: "$",
                show_cta: true,
                cta_text: "Add to Cart",
                cta_style: "primary"
              )
            end
          end
        end
      end
    end
  end
  
  private
  
  def generate_sample_products
    [
      { name: "Basic Tee", variant: "Black", price: 35, color: "black", category: "shirts", 
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg" },
      { name: "Basic Tee", variant: "White", price: 35, color: "white", category: "shirts",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-01.jpg" },
      { name: "Nomad Tumbler", variant: "White", price: 35, color: "white", category: "accessories",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-02.jpg" },
      { name: "Travel Mug", variant: "Black", price: 25, color: "black", category: "accessories",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-03.jpg" },
      { name: "Leather Jacket", variant: "Brown", price: 250, color: "brown", category: "outerwear",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-03.jpg" },
      { name: "Cotton Hoodie", variant: "Gray", price: 89, color: "gray", category: "outerwear",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-02.jpg" },
      { name: "Wool Blanket", variant: "Brown", price: 120, color: "brown", category: "home",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-04.jpg" },
      { name: "Machined Pen", variant: "Black", price: 35, color: "black", category: "accessories",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-01.jpg" }
    ]
  end
end
