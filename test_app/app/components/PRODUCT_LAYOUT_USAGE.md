# ProductLayoutComponent Usage Guide

The `ProductLayoutComponent` is a flexible e-commerce layout component that accepts Rails objects (Active Record models or plain hashes) containing product information.

## Basic Usage

```erb
<%= render ProductLayoutComponent.new(
  products: @products,  # Array of product objects
  title: "Our Products",
  columns: 4,
  currency: "$"
) %>
```

## Product Object Requirements

The component is designed to work with any Rails object that responds to these methods (or hash keys):

- `id` - Product identifier
- `name` or `title` - Product name
- `description` or `summary` - Product description (optional)
- `price` or `amount` - Product price
- `image_url`, `image`, or `photo` - Product image (supports Active Storage)

### Example with Active Record

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  has_one_attached :photo
  
  # Your model just needs these attributes/methods
  # - name: string
  # - description: text
  # - price: decimal
  # - image_url: string (or use Active Storage photo)
end

# In your controller
@products = Product.featured.limit(12)

# In your view
<%= render ProductLayoutComponent.new(products: @products) %>
```

### Example with Plain Hashes

```erb
<% products = [
  { 
    id: 1, 
    name: "Coffee Mug", 
    price: 15.99, 
    image_url: "https://example.com/mug.jpg",
    description: "Premium ceramic mug"
  },
  { 
    id: 2, 
    name: "T-Shirt", 
    price: 25.99, 
    image_url: "https://example.com/shirt.jpg" 
  }
] %>

<%= render ProductLayoutComponent.new(products: products) %>
```

## Configuration Options

### Layout Options
- `columns` (Integer, default: 4) - Number of columns (1, 2, 3, 4, or 6)
- `gap` (Integer, default: 6) - Gap between products
- `title` (String) - Optional title for the layout

### Filter Options
- `show_filters` (Boolean, default: true) - Show/hide filters
- `filter_position` (String, default: "top") - "top" or "sidebar"
- `filterable_attributes` (Array, default: [:price, :color, :category]) - Which filters to show

### Product Card Options
- `show_image` (Boolean, default: true)
- `show_price` (Boolean, default: true)
- `show_description` (Boolean, default: false)
- `currency` (String, default: "$")
- `image_aspect` (String, default: "square") - "square", "video", or "portrait"

### CTA Button Options
- `show_cta` (Boolean, default: true)
- `cta_text` (String, default: "Add to Cart")
- `cta_style` (String, default: "primary") - "primary", "secondary", or "outline"

### Sort Options
- `show_sort` (Boolean, default: true)
- `sort_options` (Array) - Custom sort options

## Using Slots for Customization

The component provides slots for advanced customization:

### Header Actions Slot
```erb
<%= render ProductLayoutComponent.new(products: @products) do |component| %>
  <% component.with_header_actions do %>
    <%= link_to "Add Product", new_product_path, class: "btn btn-primary" %>
    <%= button_tag "Export", class: "btn btn-secondary" %>
  <% end %>
<% end %>
```

### Custom Filters Slot
```erb
<%= render ProductLayoutComponent.new(products: @products) do |component| %>
  <% component.with_filters do %>
    <div class="custom-filters">
      <%= form_with url: products_path, method: :get do |f| %>
        <%= f.text_field :search, placeholder: "Search products..." %>
        <%= f.select :category, options_for_select(@categories) %>
        <%= f.submit "Filter" %>
      <% end %>
    </div>
  <% end %>
<% end %>
```

### Footer Slot
```erb
<%= render ProductLayoutComponent.new(products: @products) do |component| %>
  <% component.with_footer do %>
    <%= paginate @products %>
  <% end %>
<% end %>
```

### Custom Product Cards
For complete control over product card rendering:

```erb
<%= render ProductLayoutComponent.new(products: @products) do |component| %>
  <% @products.each_with_index do |product, index| %>
    <% component.with_product_card(product: product, index: index) do %>
      <!-- Your custom product card HTML -->
      <div class="custom-card">
        <%= image_tag product.image_url %>
        <h3><%= product.name %></h3>
        <p><%= number_to_currency(product.price) %></p>
        <%= button_to "Buy Now", add_to_cart_path(product) %>
      </div>
    <% end %>
  <% end %>
<% end %>
```

## Real-World Example

```erb
# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  def index
    @products = Product.includes(:photo_attachment)
                      .filter_by_params(params)
                      .page(params[:page])
    @categories = Category.all
  end
end

# app/views/products/index.html.erb
<%= render ProductLayoutComponent.new(
  products: @products,
  title: "Shop All Products",
  columns: 3,
  show_filters: true,
  filter_position: "sidebar",
  show_description: true,
  currency: current_user.preferred_currency || "$"
) do |component| %>
  
  <% component.with_header_actions do %>
    <div class="flex items-center gap-4">
      <span class="text-sm text-gray-600">
        <%= @products.total_count %> products found
      </span>
      <%= link_to "View Saved Items", saved_items_path, 
          class: "text-blue-600 hover:text-blue-700" %>
    </div>
  <% end %>
  
  <% component.with_filters do %>
    <%= render "products/filters", 
        categories: @categories,
        current_filters: params[:filters] %>
  <% end %>
  
  <% component.with_footer do %>
    <div class="mt-8 border-t pt-8">
      <%= paginate @products %>
    </div>
  <% end %>
  
<% end %>
```

## Active Storage Support

The component automatically detects and handles Active Storage attachments:

```ruby
class Product < ApplicationRecord
  has_one_attached :photo
end

# The component will automatically use:
# - product.photo if it's attached
# - product.image_url as fallback
# - product[:image_url] for hash objects
```

## Declaring interactions

Application behavior stays in the Ruby component. Declare a signed action and
let RenderIR plus the gem-owned runtime transport the click and apply the keyed
result:

```ruby
button("Add to cart").on_click do
  # Re-load and authorize from the captured scalar ID on every request.
  product = Current.user.available_products.find(product_id)
  Current.user.cart.add(product)
end
```

Do not add a JavaScript controller, `data-action`, target, selector, or direct
DOM mutation. If a browser behavior is missing, add it to the bounded semantic
DSL and RenderIR command vocabulary first.

## Testing

```ruby
test "renders products correctly" do
  products = [
    { id: 1, name: "Test Product", price: 99.99 },
    { id: 2, name: "Another Product", price: 49.99 }
  ]
  
  render_inline(ProductLayoutComponent.new(
    products: products,
    columns: 2
  ))
  
  assert_text "Test Product"
  assert_text "$99.99"
  assert_selector "[data-product-id='1']"
end
```
