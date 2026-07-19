# frozen_string_literal: true

require "test_helper"

module Showcase
  class CommerceServicesTest < ActiveSupport::TestCase
    setup do
      @catalog = Catalog.new
    end

    test "catalog combines search filters and deterministic sorting" do
      results = @catalog.search(
        query: "USB-C",
        category: "audio",
        max_price_cents: 35_000,
        in_stock: true,
        sort: "price_asc"
      )

      assert_equal [ "aurora-headphones" ], results.map(&:id)
      assert_equal @catalog.all.length, @catalog.all.map(&:id).uniq.length
      assert_equal %w[audio imaging studio travel workspace], @catalog.categories.keys.sort
    end

    test "cart normalizes untrusted session values" do
      cart = Cart.new(
        {
          "aurora-headphones" => "99",
          "field-recorder" => "2",
          "../../admin" => "4",
          "orbit-keyboard" => "-2",
          "arc-dock" => Object.new
        },
        catalog: @catalog
      )

      assert_equal({ "aurora-headphones" => Cart::MAX_QUANTITY }, cart.to_session)
      assert_equal Cart::MAX_QUANTITY, cart.item_count
    end

    test "cart enforces stock and maximum quantities" do
      cart = Cart.new({}, catalog: @catalog)

      error = assert_raises(Cart::InvalidOperation) { cart.add("field-recorder", 1) }
      assert_match(/sold out/, error.message)

      cart.add("pulse-monitors", 4)
      assert_raises(Cart::InvalidOperation) { cart.add("pulse-monitors", 1) }
      assert_raises(Cart::InvalidOperation) { cart.update("pulse-monitors", "9") }
      assert_equal 4, cart.item_count
    end

    test "update and remove cannot be used to create absent cart lines" do
      cart = Cart.new({}, catalog: @catalog)

      assert_raises(Cart::InvalidOperation) { cart.update("orbit-keyboard", 1) }
      assert_raises(Cart::InvalidOperation) { cart.remove("orbit-keyboard") }
      assert cart.empty?
    end

    test "cart calculates delivery threshold and totals in integer pence" do
      cart = Cart.new({}, catalog: @catalog)
      cart.add("compass-charger", 1)

      assert_equal 7_900, cart.subtotal_cents
      assert_equal Cart::SHIPPING_CENTS, cart.shipping_cents
      assert_equal 9_400, cart.total_cents

      cart.add("canvas-display", 1)
      assert_equal 0, cart.shipping_cents
      assert_equal 77_800, cart.total_cents
    end

    test "checkout normalizes bounded fields and reports useful errors" do
      checkout = Checkout.new(
        name: "   A   ",
        email: "not-an-email",
        address: "short",
        ignored: "must not matter"
      )

      refute checkout.valid?
      assert_equal "A", checkout.name
      assert_equal %i[name email address], checkout.errors.keys

      valid_checkout = Checkout.new(
        name: "  Ada   Lovelace ",
        email: "ada@example.test",
        address: "12 Analytical Engine Way, London"
      )
      assert valid_checkout.valid?
      assert_equal "Ada Lovelace", valid_checkout.name

      oversized_checkout = Checkout.new(
        name: "Ada Lovelace",
        email: "a" * (Checkout::MAX_LENGTHS[:email] + 1),
        address: "12 Analytical Engine Way, London"
      )
      refute oversized_checkout.valid?
      assert_equal [ "Email is too long." ], oversized_checkout.errors[:email]
    end

    test "checkout refuses an empty cart and returns a non-sensitive order record" do
      checkout = Checkout.new(
        name: "Ada Lovelace",
        email: "ada@example.test",
        address: "12 Analytical Engine Way, London"
      )

      assert_raises(ArgumentError) { checkout.place_order(Cart.new({}, catalog: @catalog)) }

      cart = Cart.new({ "orbit-keyboard" => 1 }, catalog: @catalog)
      order = checkout.place_order(cart)
      assert_match(/\ASRV-[A-F0-9]{6}\z/, order[:reference])
      assert_equal cart.total_cents, order[:total_cents]
      assert_equal "ada@example.test", order[:email]
      refute order.key?(:address)
      refute order.key?(:name)
    end
  end
end
