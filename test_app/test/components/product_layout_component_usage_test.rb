# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ProductLayoutComponentUsageTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers
  
  test "works with Rails Active Record objects" do
    # Mock product objects (in real app these would be AR models)
    products = [
      OpenStruct.new(
        id: 1,
        name: "MacBook Pro",
        description: "Powerful laptop for professionals",
        price: 2499.99,
        image_url: "https://example.com/macbook.jpg"
      ),
      OpenStruct.new(
        id: 2,
        name: "iPhone 15",
        description: "Latest smartphone",
        price: 999.99,
        image_url: "https://example.com/iphone.jpg"
      )
    ]
    
    # Basic usage
    component = ProductLayoutComponent.new(
      products: products,
      title: "Featured Products",
      columns: 2,
      currency: "$"
    )
    
    render_inline(component)
    
    assert_text "Featured Products"
    assert_text "2 items"
    assert_text "MacBook Pro"
    assert_text "$2499.99"
    assert_text "iPhone 15"
    assert_text "$999.99"
  end
  
  test "works with hash objects" do
    # Can also use plain hashes
    products = [
      { id: 1, name: "Coffee Mug", price: 15.99, image_url: "mug.jpg" },
      { id: 2, name: "T-Shirt", price: 25.99, image_url: "shirt.jpg" }
    ]
    
    component = ProductLayoutComponent.new(
      products: products,
      show_filters: false,
      columns: 2
    )
    
    render_inline(component)
    
    assert_text "Coffee Mug"
    assert_text "$15.99"
  end
  
  test "supports custom slots" do
    products = [{ id: 1, name: "Test Product", price: 99.99 }]
    
    component = ProductLayoutComponent.new(products: products)
    view = vc_test_controller.view_context

    render_inline(component) do |c|
      # Custom header actions
      c.with_header_actions do
        view.tag.button("Export CSV", class: "btn btn-secondary")
      end
      
      # Custom filters
      c.with_filters do
        view.tag.div(class: "custom-filters") do
          view.tag.h3("Custom Filters") +
          view.tag.input(type: "text", placeholder: "Search products...")
        end
      end
      
      # Custom footer
      c.with_footer do
        view.tag.div("Showing 1 of 100 products", class: "text-gray-600")
      end
    end

    assert_selector "button", text: "Export CSV"
    assert_selector "h3", text: "Custom Filters"
    assert_text "Showing 1 of 100 products"
  end
  
  test "supports Active Storage images" do
    # Mock product with Active Storage attachment
    product = OpenStruct.new(
      id: 1,
      name: "Product with Photo",
      price: 49.99,
      photo: OpenStruct.new(
        attached?: true,
        url: "https://picsum.photos/400/400"
      )
    )
    
    # Override rails_blob_url for testing
    component = ProductLayoutComponent.new(products: [product])
    def component.rails_blob_url(attachment)
      attachment.url
    end
    
    render_inline(component)
    
    assert_selector "img[src='https://picsum.photos/400/400']"
  end
end
