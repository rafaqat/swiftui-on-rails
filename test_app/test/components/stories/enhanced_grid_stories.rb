# frozen_string_literal: true

class EnhancedGridStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::Helpers
  include SwiftUIRails::DSL
  
  # Demonstrate responsive grid with custom breakpoints
  def responsive_custom(**kwargs)
    products = generate_sample_products[0..11] # 12 products
    
    swift_ui do
      section.bg("white").p(8) do
        # Title
        text("Custom Responsive Grid").text_size("3xl").font_weight("bold").mb(2)
        text("Resize window to see responsive behavior").text_color("gray-600").mb(8)
        
        # Grid with custom responsive breakpoints
        grid(
          columns: { base: 1, sm: 2, md: 3, lg: 4, xl: 6 },
          spacing: 6
        ) do
          products.each do |product|
            dsl_product_card(
              name: product[:name],
              price: product[:price],
              image_url: product[:image],
              variant: product[:variant]
            )
          end
        end
      end
    end
  end
  
  # Auto-fit grid based on minimum item width
  def auto_fit_grid(**kwargs)
    products = generate_sample_products[0..7]
    
    swift_ui do
      section.bg("gray-50").p(8) do
        # Title
        text("Auto-Fit Grid").text_size("3xl").font_weight("bold").mb(2)
        text("Items auto-fit based on 280px minimum width").text_color("gray-600").mb(8)
        
        # Auto-fit grid
        grid(
          min_item_width: 280,
          spacing: 6,
          auto_rows: "minmax(350px, auto)"
        ) do
          products.each do |product|
            dsl_product_card(
              name: product[:name],
              price: product[:price],
              image_url: product[:image],
              variant: product[:variant],
              show_cta: true
            )
          end
        end
      end
    end
  end
  
  # Different row and column gaps
  def asymmetric_gaps(**kwargs)
    categories = [
      { name: "Electronics", count: 245, icon: "📱", color: "blue" },
      { name: "Clothing", count: 189, icon: "👕", color: "green" },
      { name: "Home & Garden", count: 156, icon: "🏠", color: "yellow" },
      { name: "Sports", count: 134, icon: "⚽", color: "red" },
      { name: "Books", count: 98, icon: "📚", color: "purple" },
      { name: "Toys", count: 76, icon: "🧸", color: "pink" }
    ]
    
    swift_ui do
      section.bg("white").p(8) do
        # Title
        text("Category Grid with Asymmetric Gaps").text_size("3xl").font_weight("bold").mb(2)
        text("More vertical space (12) than horizontal (4)").text_color("gray-600").mb(8)
        
        # Grid with different gaps
        grid(
          columns: 3,
          row_gap: 12,
          column_gap: 4,
          align: :stretch,
          auto_rows: :fr
        ) do
          categories.each do |category|
            card.p(8).hover_scale(105).shadow("lg").transition do
              vstack(spacing: 4, alignment: :center) do
                # Icon
                text(category[:icon]).text_size("6xl")
                
                # Category name
                text(category[:name])
                  .text_size("xl")
                  .font_weight("semibold")
                  .text_color("gray-900")
                
                # Product count
                text("#{category[:count]} products")
                  .text_size("sm")
                  .text_color("gray-600")
                
                # View button
                button("Browse")
                  .mt(4)
                  .w("full")
                  .bg("#{category[:color]}-500")
                  .text_color("white")
                  .py(2)
                  .rounded("md")
                  .hover("bg-#{category[:color]}-600")
              end
            end
          end
        end
      end
    end
  end
  
  # Equal height rows with varied content
  def equal_height_rows(**kwargs)
    products = [
      { name: "Premium Wireless Headphones with Active Noise Cancellation", price: 299, description: "Experience crystal-clear audio with our top-of-the-line headphones." },
      { name: "Smart Watch", price: 199, description: "Track fitness and stay connected." },
      { name: "Portable Bluetooth Speaker", price: 79, description: "Take your music anywhere with powerful, room-filling sound and 24-hour battery life." },
      { name: "USB-C Hub", price: 49, description: "Expand your connectivity." }
    ]
    
    swift_ui do
      section.bg("gray-100").p(8) do
        # Title
        text("Equal Height Grid").text_size("3xl").font_weight("bold").mb(2)
        text("All cards have equal height despite different content").text_color("gray-600").mb(8)
        
        # Grid with equal height rows
        grid(
          columns: 2,
          spacing: 6,
          auto_rows: :fr,  # Equal height rows
          align: :stretch  # Stretch items to fill
        ) do
          products.each do |product|
            card.p(6).h("full").flex.tw("flex-col") do
              # Product name
              text(product[:name])
                .text_size("lg")
                .font_weight("semibold")
                .text_color("gray-900")
                .mb(2)
              
              # Description
              text(product[:description])
                .text_color("gray-600")
                .text_size("sm")
                .flex_grow  # Take available space
              
              # Price and CTA at bottom
              div.mt(4) do
                text("$#{product[:price]}")
                  .text_size("2xl")
                  .font_weight("bold")
                  .text_color("gray-900")
                  .mb(3)
                
                button("Add to Cart")
                  .w("full")
                  .bg("indigo-600")
                  .text_color("white")
                  .py(2)
                  .rounded("md")
                  .hover("bg-indigo-700")
              end
            end
          end
        end
      end
    end
  end
  
  # Dense packing for mixed sizes
  def dense_packing(**kwargs)
    products = generate_sample_products[0..7]
    
    swift_ui do
      section.bg("white").p(8) do
        # Title
        text("Dense Grid Packing").text_size("3xl").font_weight("bold").mb(2)
        text("Featured items span 2 columns, dense packing fills gaps").text_color("gray-600").mb(8)
        
        # Dense grid
        grid(
          columns: 4,
          spacing: 4,
          auto_flow: :dense,
          align: :start
        ) do
          products.each_with_index do |product, i|
            # Make some items featured (2x2)
            if [1, 4].include?(i)
              div.col_span(2).row_span(2) do
                card.p(8).h("full").tw("bg-gradient-to-br from-purple-500 to-pink-500") do
                  vstack(spacing: 4, alignment: :center) do
                    text("FEATURED").text_color("white").font_weight("bold")
                    
                    if product[:image]
                      div.aspect_ratio("square").overflow("hidden").rounded("lg").bg("white/20") do
                        image(src: product[:image], alt: product[:name])
                          .w("full").h("full").object_fit("cover")
                      end
                    end
                    
                    text(product[:name])
                      .text_color("white")
                      .text_size("2xl")
                      .font_weight("bold")
                      .text_align("center")
                    
                    text("$#{product[:price]}")
                      .text_color("white")
                      .text_size("3xl")
                      .font_weight("bold")
                    
                    button("Shop Now")
                      .bg("white")
                      .text_color("purple-600")
                      .px(8)
                      .py(3)
                      .rounded("full")
                      .font_weight("semibold")
                      .hover("bg-gray-100")
                      .mt(4)
                  end
                end
              end
            else
              # Regular product card
              dsl_product_card(
                name: product[:name],
                price: product[:price],
                image_url: product[:image],
                variant: product[:variant]
              )
            end
          end
        end
      end
    end
  end
  
  # Centered grid with spacing
  def centered_grid(**kwargs)
    featured = generate_sample_products[0..2] # Just 3 items
    
    swift_ui do
      section.bg("gray-50").min_h("screen").flex.items_center.justify_center.p(8) do
        div.max_w("6xl").w("full") do
          # Title
          vstack(spacing: 2, alignment: :center).mb(12) do
            text("Featured Collection").text_size("4xl").font_weight("bold").text_color("gray-900")
            text("Hand-picked items just for you").text_size("xl").text_color("gray-600")
          end
          
          # Centered grid
          grid(
            columns: 3,
            spacing: 8,
            justify: :center,
            align: :center
          ) do
            featured.each do |product|
              dsl_product_card(
                name: product[:name],
                price: product[:price],
                image_url: product[:image],
                variant: product[:variant],
                show_cta: true,
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
      { name: "Basic Tee", variant: "Black", price: 35, color: "black", 
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-04.jpg" },
      { name: "Basic Tee", variant: "White", price: 35, color: "white",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-01.jpg" },
      { name: "Nomad Tumbler", variant: "White", price: 35, color: "white",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-02.jpg" },
      { name: "Travel Mug", variant: "Black", price: 25, color: "black",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-03.jpg" },
      { name: "Leather Jacket", variant: "Brown", price: 250, color: "brown",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-03.jpg" },
      { name: "Cotton Hoodie", variant: "Gray", price: 89, color: "gray",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/product-page-01-related-product-02.jpg" },
      { name: "Wool Blanket", variant: "Brown", price: 120, color: "brown",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-04.jpg" },
      { name: "Machined Pen", variant: "Black", price: 35, color: "black",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-01.jpg" },
      { name: "Leather Wallet", variant: "Brown", price: 65, color: "brown",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/home-page-04-trending-product-02.jpg" },
      { name: "Ceramic Mug", variant: "White", price: 18, color: "white",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-02.jpg" },
      { name: "Metal Water Bottle", variant: "Silver", price: 42, color: "silver",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/category-page-04-image-card-03.jpg" },
      { name: "Canvas Tote", variant: "Natural", price: 28, color: "beige",
        image: "https://tailwindcss.com/plus-assets/img/ecommerce-images/shopping-cart-page-04-product-01.jpg" }
    ]
  end
end