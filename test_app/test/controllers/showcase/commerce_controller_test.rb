# frozen_string_literal: true

require "test_helper"

module Showcase
  class CommerceControllerTest < ActionDispatch::IntegrationTest
    test "shows a complete accessible catalog and empty states" do
      get showcase_commerce_path

      assert_response :success
      assert_select "h1", text: /Make room for/
      assert_select "article.commerce-product-card", count: Catalog::PRODUCTS.length
      assert_select "#commerce_cart", count: 1
      assert_select "#commerce_checkout", count: 1
      assert_select ".commerce-empty-cart", text: /Your bag is ready/
      assert_select "form[action='#{showcase_commerce_path}'][method='get']"
      assert_select "div.commerce-layout", count: 1
      assert_select "main.commerce-layout", count: 0
    end

    test "allowlists and combines catalog parameters" do
      get showcase_commerce_path,
        params: {
          q: "  usb-c  ",
          category: "audio",
          max_price: "35000",
          in_stock: "1",
          sort: "price_asc",
          admin: "true"
        }

      assert_response :success
      assert_select "article.commerce-product-card", count: 1
      assert_select "h3", text: "Aurora Studio Headphones"
      assert_select "h3", text: "Field Notes Recorder", count: 0
      assert_select "input[name='q'][value='usb-c']"
      assert_select "option[value='audio'][selected]"
    end

    test "rejects invalid filter values and bounds a long query" do
      get showcase_commerce_path,
        params: {
          q: "x" * 500,
          category: "../../admin",
          max_price: "999999999999",
          sort: "constantize"
        }

      assert_response :success
      assert_select "input[name='q']" do |inputs|
        assert_equal CommerceController::MAX_QUERY_LENGTH, inputs.first["value"].length
      end
      assert_select "option[value='featured'][selected]"
      assert_select "option[value='../../admin']", count: 0
    end

    test "renders product detail in the quick view frame and returns 404 for unknown ids" do
      get showcase_commerce_product_path("aurora-headphones")

      assert_response :success
      assert_select "turbo-frame#commerce_quick_view"
      assert_select "h1", text: "Aurora Studio Headphones"
      assert_select "li", text: "40-hour battery"

      get showcase_commerce_product_path("missing-product")
      assert_response :not_found
      assert_equal "Product not found", response.body
    end

    test "HTML cart flow adds updates and removes products" do
      post showcase_commerce_cart_items_path,
        params: { product_id: "orbit-keyboard", quantity: "2" }
      assert_redirected_to showcase_commerce_path

      follow_redirect!
      assert_select ".commerce-cart-line", count: 1
      assert_select ".commerce-count-dark", text: "2"
      assert_select ".commerce-grand-total dd", text: "£373.00"

      patch showcase_commerce_cart_item_path("orbit-keyboard"), params: { quantity: "1" }
      assert_redirected_to showcase_commerce_path
      follow_redirect!
      assert_select ".commerce-count-dark", text: "1"

      delete showcase_commerce_cart_item_path("orbit-keyboard")
      assert_redirected_to showcase_commerce_path
      follow_redirect!
      assert_select ".commerce-empty-cart", count: 1
    end

    test "Turbo cart flow replaces cart and checkout regions" do
      post showcase_commerce_cart_items_path,
        params: { product_id: "compass-charger", quantity: "1" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      assert_response :success
      assert_equal Mime[:turbo_stream].to_s, response.media_type
      assert_select "turbo-stream[action='replace'][target='commerce_cart']", count: 1
      assert_select "turbo-stream[action='replace'][target='commerce_checkout']", count: 1
      assert_select "turbo-stream[action='update'][target='commerce_nav_count']", count: 1
      assert_select "turbo-stream[action='update'][target='commerce_notice']", count: 1
      assert_includes response.body, "Compass Travel Charger"
    end

    test "invalid quantities and sold-out products do not mutate the cart" do
      post showcase_commerce_cart_items_path,
        params: { product_id: "field-recorder", quantity: "1" }
      assert_redirected_to showcase_commerce_path
      follow_redirect!
      assert_select ".commerce-notice--error", text: /sold out/
      assert_select ".commerce-empty-cart"

      post showcase_commerce_cart_items_path,
        params: { product_id: "orbit-keyboard", quantity: "999" }
      follow_redirect!
      assert_select ".commerce-notice--error", text: /between 1 and 8/
      assert_select ".commerce-empty-cart"
    end

    test "checkout renders errors and preserves allowlisted values" do
      post showcase_commerce_cart_items_path,
        params: { product_id: "arc-dock", quantity: "1" }

      post showcase_commerce_checkout_path,
        params: {
          checkout: {
            name: "A",
            email: "bad-email",
            address: "short",
            card_number: "4111111111111111"
          }
        }

      assert_response :unprocessable_entity
      assert_select ".commerce-form-errors li", count: 3
      assert_select "input[name='checkout[name]'][value='A']"
      assert_select "input[name='checkout[email]'][value='bad-email']"
      assert_select "input[name='checkout[card_number]']", count: 0
      assert_select ".commerce-cart-line", count: 1
    end

    test "successful HTML checkout confirms an order and empties the cart" do
      post showcase_commerce_cart_items_path,
        params: { product_id: "arc-dock", quantity: "1" }

      post showcase_commerce_checkout_path,
        params: valid_checkout_params

      assert_response :see_other
      follow_redirect!
      assert_select ".commerce-success", text: /Thank you/
      assert_select ".commerce-success", text: /SRV-[A-F0-9]{6}/
      assert_select ".commerce-empty-cart", count: 1
    end

    test "Turbo checkout returns errors and success as scoped stream updates" do
      post showcase_commerce_checkout_path,
        params: valid_checkout_params,
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      assert_response :unprocessable_entity
      assert_select "turbo-stream[target='commerce_checkout']"
      assert_includes response.body, "Your bag is empty"

      post showcase_commerce_cart_items_path,
        params: { product_id: "canvas-display", quantity: "1" }
      post showcase_commerce_checkout_path,
        params: valid_checkout_params,
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      assert_response :success
      assert_select "turbo-stream[action='replace'][target='commerce_cart']"
      assert_select "turbo-stream[action='replace'][target='commerce_checkout']"
      assert_select ".commerce-success", count: 1
      assert_match(/SRV-[A-F0-9]{6}/, response.body)
    end

    private

    def valid_checkout_params
      {
        checkout: {
          name: "Ada Lovelace",
          email: "ada@example.test",
          address: "12 Analytical Engine Way, London"
        }
      }
    end
  end
end
