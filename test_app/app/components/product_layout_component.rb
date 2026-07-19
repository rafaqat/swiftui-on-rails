# frozen_string_literal: true

class ProductLayoutComponent < ApplicationComponent
  # Main props - accepts Rails AR objects or hashes
  prop :products, type: Array, required: true
  prop :title, type: String, default: "Products"
  prop :columns, type: [Integer, Hash], default: 4 # fixed or responsive columns
  prop :gap, type: Integer, default: 6
  
  # Filter options
  prop :show_filters, type: [TrueClass, FalseClass], default: true
  prop :filter_position, type: String, default: "top" # top, sidebar
  prop :filterable_attributes, type: Array, default: [:price, :color, :category]
  
  # Product card options
  prop :show_image, type: [TrueClass, FalseClass], default: true
  prop :show_price, type: [TrueClass, FalseClass], default: true
  prop :show_description, type: [TrueClass, FalseClass], default: false
  prop :currency, type: String, default: "$"
  prop :image_aspect, type: String, default: "square" # square, video, portrait
  
  # CTA options
  prop :show_cta, type: [TrueClass, FalseClass], default: true
  prop :cta_text, type: String, default: "Add to Cart"
  prop :cta_style, type: String, default: "primary" # primary, secondary, outline
  
  # Sort options
  prop :show_sort, type: [TrueClass, FalseClass], default: true
  prop :sort_options, type: Array, default: [
    { value: "popular", label: "Most Popular" },
    { value: "newest", label: "Newest" },
    { value: "price_asc", label: "Price: Low to High" },
    { value: "price_desc", label: "Price: High to Low" }
  ]
  
  swift_ui do
    comp = @component

    section.bg("gray-50").min_h("screen") do
      div.max_w("7xl").mx("auto").px(4).py(8).add_class("sm:px-6 lg:px-8") do
        # Header with title and sort
        if title.present? || show_sort || comp.header_actions?
          hstack(alignment: :center).mb(8) do
            if title.present?
              vstack(alignment: :start, spacing: 2) do
                text(title)
                  .text_size("3xl")
                  .font_weight("bold")
                  .text_color("gray-900")
                
                text("#{products.count} items")
                  .text_size("base")
                  .text_color("gray-600")
              end
            end
            
            spacer
            
            # Sort dropdown
            if show_sort
              render_sort_dropdown
            end
            
            # Custom header actions slot
            if comp.header_actions?
              div.ml(4) { comp.header_actions }
            end
          end
        end
        
        # Main layout based on filter position
        if show_filters && filter_position == "top"
          # Top filters layout
          vstack(spacing: 6) do
            render_top_filters if comp.filters?
            # Inline the grid rendering to ensure it's in DSL context
            Rails.logger.debug "ProductLayoutComponent: Calling grid with columns: #{columns}, gap: #{gap}"
            grid(columns: columns, spacing: gap) do
              products.each_with_index do |product, index|
                Rails.logger.debug "Rendering product #{index}: #{product[:name]}"
                
                # Use the reusable DSL product card method
                dsl_product_card(
                  name: product_name(product),
                  price: product_price(product),
                  image_url: show_image ? product_image_url(product) : nil,
                  variant: product[:variant] || product[:color],
                  currency: currency,
                  show_cta: show_cta,
                  cta_text: cta_text,
                  cta_style: cta_style
                )
              end
            end
          end
        elsif show_filters && filter_position == "sidebar"
          # Sidebar layout
          hstack(spacing: 8, alignment: :start) do
            # Filters sidebar
            if comp.filters?
              div.w(64).flex_shrink(0) do
                div.sticky.top(8) { comp.filters }
              end
            end
            
            # Product grid
            div.flex_1 do
              # Inline the grid rendering to ensure it's in DSL context
              grid(columns: columns, spacing: gap) do
                products.each_with_index do |product, index|
                  Rails.logger.debug "Rendering product #{index}: #{product[:name]}"
                  
                  # Create product card - each DSL method call needs to be properly chained
                  card do
                    # Product image container with DSL chaining
                    if show_image && product_image_url(product)
                      div do
                        image(
                          src: product_image_url(product),
                          alt: product_name(product)
                        )
                      end.aspect_ratio(image_aspect).overflow("hidden").bg("gray-200")
                    end
                    
                    # Product details using vstack DSL
                    vstack(spacing: 2, alignment: :start) do
                      # Product name with full DSL chaining
                      text(product_name(product))
                        .font_weight("semibold")
                        .text_color("gray-900")
                        .text_size("lg")
                        .line_clamp(1)
                      
                      # Product variant/color with DSL chaining
                      if product[:variant] || product[:color]
                        text(product[:variant] || product[:color])
                          .text_color("gray-600")
                          .text_size("sm")
                      end
                      
                      # Price with DSL chaining
                      if show_price
                        text("#{currency}#{product_price(product)}")
                          .font_weight("bold")
                          .text_color("gray-900")
                          .text_size("xl")
                          .mt(2)
                      end
                      
                      # CTA button with full DSL chaining
                      if show_cta
                        button(cta_text)
                          .w("full")
                          .px(4).py(2)
                          .mt(4)
                          .bg("black")
                          .text_color("white")
                          .rounded("md")
                          .hover("bg-gray-800")
                          .transition
                          .font_weight("medium")
                      end
                    end.p(4)
                  end.bg("white").rounded("lg").shadow("md").overflow("hidden")
                end
              end
            end
          end
        else
          # No filters - just grid
          # Need to wrap in a div to ensure the element is captured
          div do
            # Inline the grid rendering to ensure it's in DSL context
            Rails.logger.debug "ProductLayoutComponent: Calling grid with columns: #{columns}, gap: #{gap}"
            grid(columns: columns, spacing: gap) do
              products.each_with_index do |product, index|
                Rails.logger.debug "Rendering product #{index}: #{product[:name]}"
                
                # Use the reusable DSL product card method
                dsl_product_card(
                  name: product_name(product),
                  price: product_price(product),
                  image_url: show_image ? product_image_url(product) : nil,
                  variant: product[:variant] || product[:color],
                  currency: currency,
                  show_cta: show_cta,
                  cta_text: cta_text,
                  cta_style: cta_style
                )
              end
            end
          end
        end
        
        # Footer slot
        if comp.footer?
          div.mt(12) { comp.footer }
        end
      end
    end
  end
  
  private
  
  
  def render_sort_dropdown
    div.relative do
      select_element
        .block.w("full").pl(3).pr(10).py(2)
        .text_size("base").border("gray-300").rounded("md")
        .add_class("focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm") do
        sort_options.each do |option|
          option_element(option[:label], value: option[:value])
        end
      end
    end
  end
  
  def render_top_filters
    div.bg("white").p(6).rounded("lg").shadow("sm").border.border_color("gray-200") do
      self.filters
    end
  end
  
  def cta_button_classes
    case cta_style
    when "primary"
      "bg-black text-white rounded-md hover:bg-gray-800 transition-colors font-medium"
    when "secondary"
      "bg-gray-200 text-gray-900 rounded-md hover:bg-gray-300 transition-colors font-medium"
    when "outline"
      "border-2 border-gray-900 text-gray-900 rounded-md hover:bg-gray-900 hover:text-white transition-colors font-medium"
    else
      "bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors font-medium"
    end
  end
  
  # Helper methods to extract data from product objects/hashes
  def product_id(product)
    product.respond_to?(:id) ? product.id : product[:id]
  end
  
  def product_name(product)
    if product.respond_to?(:name)
      product.name
    elsif product.respond_to?(:title)
      product.title
    else
      product[:name] || product[:title] || "Untitled Product"
    end
  end
  
  def product_description(product)
    if product.respond_to?(:description)
      product.description
    elsif product.respond_to?(:summary)
      product.summary
    else
      product[:description] || product[:summary]
    end
  end
  
  def product_price(product)
    if product.respond_to?(:price)
      product.price
    elsif product.respond_to?(:amount)
      product.amount
    else
      product[:price] || product[:amount] || 0
    end
  end
  
  def product_image_url(product)
    if product.respond_to?(:image_url)
      product.image_url
    elsif product.respond_to?(:image) && product.image.respond_to?(:url)
      product.image.url
    elsif product.respond_to?(:photo) && product.photo.attached?
      # Active Storage support
      rails_blob_url(product.photo)
    else
      product[:image_url] || product[:image] || product[:photo_url]
    end
  end
  
  # Slots for customization
  renders_one :header_actions
  renders_one :filters
  renders_one :footer
  renders_many :product_cards
  
  # Helper methods for DSL elements
  def select_element(**attrs, &block)
    create_element(:select, nil, attrs, &block)
  end
  
  def option_element(text, **attrs)
    create_element(:option, text, attrs)
  end
end
