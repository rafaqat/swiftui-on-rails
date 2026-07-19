# frozen_string_literal: true

class ProductListComponent < ApplicationComponent
  prop :products, type: Array, required: true
  prop :title, type: String, default: "Products"
  prop :columns, type: Symbol, default: :auto
  prop :gap, type: String, default: "6"
  prop :background_color, type: String, default: "white"
  prop :title_size, type: String, default: "2xl"
  prop :title_color, type: String, default: "gray-900"
  prop :container_padding, type: String, default: "16"
  prop :max_width, type: String, default: "7xl"
  prop :image_aspect, type: String, default: "square"
  prop :show_colors, type: [TrueClass, FalseClass], default: true
  prop :currency_symbol, type: String, default: "$"
  
  # Grid column configurations
  COLUMN_CONFIGS = {
    auto: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4",
    one: "grid-cols-1",
    two: "grid-cols-1 sm:grid-cols-2", 
    three: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3",
    four: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4",
    five: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5",
    six: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6"
  }.freeze
  
  # Image aspect ratio configurations
  ASPECT_CONFIGS = {
    square: "aspect-square",
    portrait: "aspect-[3/4]",
    landscape: "aspect-[4/3]",
    auto: "lg:aspect-auto lg:h-80"
  }.freeze
  
  swift_ui do
    div.bg(background_color) do
      div
        .mx("auto")
        .max_w(max_width)
        .px(4)
        .py(container_padding)
        .sm("px-6 py-#{container_padding.to_i + 8}")
        .lg("px-8") do
        
        # Title section
        if title.present?
          h2(title)
            .text_size(title_size)
            .font_weight("bold")
            .tracking("tight")
            .text_color(title_color)
        end
        
        # Products grid
        grid_column_classes = COLUMN_CONFIGS[columns] || COLUMN_CONFIGS[:auto]
        div
          .mt(6)
          .grid_class
          .gap_x(gap)
          .gap_y(10)
          .xl("gap-x-8")
          .tw(grid_column_classes) do
          
          products.each do |product|
            # Product card
            div.group.relative do
              # Product image with link
              link(destination: product_url(product)) do
                image(
                  src: product_image_url(product),
                  alt: product_alt_text(product)
                )
                .tw(ASPECT_CONFIGS[image_aspect.to_sym] || ASPECT_CONFIGS[:square])
                .w_full
                .rounded("md")
                .bg("gray-200")
                .object("cover")
                .group_hover("opacity-75")
              end
              
              # Product details
              div.mt(4).flex.justify_between do
                div do
                  # Product name with link
                  h3.text_size("sm").text_color("gray-700") do
                    link(destination: product_url(product))
                      .hover_text_color("gray-900")
                      .transition_colors do
                      span.absolute.inset(0).aria_hidden(true)
                      text(product_name(product))
                    end
                  end
                  
                  # Product color/variant (if enabled and available)
                  if show_colors && product_color(product).present?
                    p(product_color(product))
                      .mt(1)
                      .text_size("sm")
                      .text_color("gray-500")
                  end
                end
                
                # Product price
                p(formatted_price(product))
                  .text_size("sm")
                  .font_weight("medium")
                  .text_color("gray-900")
              end
            end
          end
        end
      end
    end
  end
  
  # Product data extraction methods - override these for custom product structures
  def product_name(product)
    product.try(:name) || product.try(:title) || product[:name] || product[:title] || "Product"
  end
  
  def product_image_url(product)
    product.try(:image_url) || product.try(:image) || product[:image_url] || product[:image] || "https://via.placeholder.com/400x400?text=No+Image"
  end
  
  def product_url(product)
    if product.respond_to?(:id)
      "/products/#{product.id}"
    elsif product[:id]
      "/products/#{product[:id]}"
    else
      "#"
    end
  end
  
  def product_color(product)
    product.try(:color) || product.try(:variant) || product[:color] || product[:variant]
  end
  
  def product_price(product)
    product.try(:price) || product[:price] || 0
  end
  
  def product_alt_text(product)
    name = product_name(product)
    color = product_color(product)
    if color.present?
      "#{name} in #{color}"
    else
      name
    end
  end
  
  def formatted_price(product)
    price = product_price(product)
    if price.is_a?(Numeric)
      "#{currency_symbol}#{price}"
    else
      price.to_s
    end
  end
end
