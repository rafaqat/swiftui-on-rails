# frozen_string_literal: true

require "test_helper"

class EnhancedProductListComponentTest < ViewComponent::TestCase
  PRODUCT = {
    id: 7,
    name: "Trail Shoe",
    color: "Blue",
    price: 42.5,
    image_url: "/shoe.png"
  }.freeze

  test "preserves the public prop contract and defaults" do
    component = EnhancedProductListComponent.new(products: [])

    assert_equal [], component.products
    assert_equal "Products", component.title
    assert_equal :auto, component.columns
    assert_equal "6", component.gap
    assert_equal "white", component.background_color
    assert_equal "16", component.container_padding
    assert_equal "7xl", component.max_width
    assert_equal true, component.enable_animations
    assert_equal "100", component.animation_delay
    assert_equal "105", component.hover_scale
    assert_equal true, component.sortable
    assert_equal %w[name price color], component.sort_options
    assert_equal "name", component.default_sort
    assert_equal "asc", component.sort_direction
    assert_equal true, component.filterable
    assert_equal true, component.filter_by_color
    assert_equal true, component.show_quick_actions
    assert_equal "$", component.currency_symbol
    assert_equal true, EnhancedProductListComponent.swift_props.dig(:products, :required)
  end

  test "renders server-owned product interactions through canonical RenderIR" do
    component = EnhancedProductListComponent.new(
      products: [ PRODUCT, PRODUCT.merge(id: 8, name: "Rain Shell", color: "Red", price: 89) ],
      title: "Featured Products",
      default_sort: "price",
      columns: :three,
      hover_scale: "110"
    )

    render_inline(component)

    root = page.find("[data-enhanced-product-list='true']", visible: :all)
    assert_equal "true", root["data-sortable"]
    assert_equal "true", root["data-filterable"]
    assert_equal %w[bg-white transition-colors duration-500 ease-in-out], root[:class].split

    assert_selector "h2", text: "Featured Products"
    assert_selector "select[data-sui-actions] option[selected]", text: "Price"
    assert_selector "button[aria-label='Reverse sort direction'][data-sui-actions] svg path", count: 1
    assert_selector "button[data-sui-actions][data-color='all']", text: "All"
    assert_selector "button[data-sui-actions][data-color='Blue']", text: "Blue"
    assert_selector "button[data-sui-actions][data-color='Red']", text: "Red"

    assert_selector "[data-product-grid='true'].grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3"
    assert_selector "[data-product-card='true']", count: 2
    assert_selector "[data-product-card='true'][data-product-id='7'][data-product-name='Trail Shoe'][data-product-price='42.5'][data-product-color='Blue'].hover\\:scale-110.hover\\:z-10"
    assert_selector "a[href='/products/7'] img[src='/shoe.png'][alt='Trail Shoe in Blue'][loading='lazy']"
    assert_selector "a[aria-label='Inspect Trail Shoe'][data-product-id='7'] svg path"
    assert_selector "[data-product-empty-state='true'].hidden", text: "No products found", visible: :all
    assert_text "$42.5"

    assert_classes(
      "select[data-sui-actions]",
      %w[rounded-md border-gray-300 text-sm focus:border-blue-500 focus:ring-blue-500]
    )
    assert_classes(
      "a[href='/products/7'] img",
      %w[aspect-square w-full rounded-md bg-gray-200 object-cover transition-transform duration-300 ease-out group-hover:scale-105]
    )
    assert_classes(
      "a[aria-label='Inspect Trail Shoe'][data-product-id='7']",
      %w[p-2 bg-white rounded-full shadow-lg hover:bg-gray-50 transition-transform duration-200 transform hover:scale-110]
    )

    document = component.last_render_ir
    assert_instance_of SwiftUIRails::RenderIR::Document, document
    assert_equal document, SwiftUIRails::RenderIR::Document.from_json(document.canonical_json)
    assert_includes document.each_node.map(&:kind), "svg"
    assert_includes document.each_node.map(&:kind), "path"
    refute document.each_node.any? { |node| node.kind == "trusted_html" }
  end

  test "preserves conditional controls quick actions and animation behavior" do
    component = EnhancedProductListComponent.new(
      products: [ PRODUCT.merge(color: nil) ],
      title: "",
      columns: :six,
      gap: "2",
      sortable: false,
      filterable: false,
      show_quick_actions: false,
      enable_animations: false,
      background_color: "gray-50",
      container_padding: "8",
      max_width: "5xl",
      currency_symbol: "£"
    )

    render_inline(component)

    assert_no_selector "h2"
    assert_no_text "Sort by:"
    assert_no_text "Filter:"
    assert_no_selector "a[aria-label^='Inspect']"
    assert_selector "[data-product-grid='true'].gap-2.xl\\:grid-cols-6"
    assert_selector "[data-product-card='true'].hover\\:scale-102.hover\\:z-10"
    assert_text "£42.5"
    assert_classes(
      "[data-enhanced-product-list='true']",
      %w[bg-gray-50 transition-colors duration-500 ease-in-out]
    )
    assert_classes(
      "[data-enhanced-product-list='true'] > div",
      %w[mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8]
    )
    assert_instance_of SwiftUIRails::RenderIR::Document, component.last_render_ir
  end


  private

  def assert_classes(selector, expected)
    assert_equal expected, page.find(selector, visible: :all)[:class].to_s.split
  end
end
