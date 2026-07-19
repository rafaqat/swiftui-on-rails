require "test_helper"

class ProductLayoutComponentTest < ViewComponent::TestCase
  def test_renders_product_grid
    products = [
      {
        id: 1,
        name: "Test Product",
        price: 29.99,
        image_url: "test.jpg",
        in_stock: true
      }
    ]
    
    component = ProductLayoutComponent.new(
      title: "Test Products",
      products: products
    )
    
    render_inline(component)
    
    assert_text "Test Products"
    assert_text "Test Product"
    assert_text "$29.99"
  end
  
  def test_renders_with_variants
    products = [
      {
        id: 1,
        name: "T-Shirt",
        price: 25,
        variant: "Small"
      }
    ]
    
    component = ProductLayoutComponent.new(products: products)
    
    render_inline(component)
    
    assert_text "T-Shirt"
    assert_text "Small"
  end
  
  def test_responsive_columns
    component = ProductLayoutComponent.new(
      products: [],
      columns: { base: 1, sm: 2, lg: 4 }
    )
    
    render_inline(component)
    
    assert_selector ".grid-cols-1"
    assert_selector ".sm\\:grid-cols-2"
    assert_selector ".lg\\:grid-cols-4"
  end
end
