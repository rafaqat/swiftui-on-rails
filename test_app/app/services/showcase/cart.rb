# frozen_string_literal: true

module Showcase
  class Cart
    MAX_QUANTITY = 8
    FREE_SHIPPING_THRESHOLD_CENTS = 50_000
    SHIPPING_CENTS = 1_500

    Line = Data.define(:product, :quantity) do
      def subtotal_cents
        product.price_cents * quantity
      end
    end

    class InvalidOperation < StandardError; end

    attr_reader :items

    def initialize(raw_items, catalog: Catalog.new)
      @catalog = catalog
      @items = normalize(raw_items)
    end

    def lines
      items.filter_map do |product_id, quantity|
        product = @catalog.find(product_id)
        Line.new(product: product, quantity: quantity) if product
      end
    end

    def add(product_id, quantity = 1)
      product = find_available_product!(product_id)
      quantity = validate_quantity!(quantity)
      new_quantity = items.fetch(product.id, 0) + quantity
      validate_stock!(product, new_quantity)
      items[product.id] = new_quantity
      self
    end

    def update(product_id, quantity)
      product = find_product!(product_id)
      ensure_present!(product)
      quantity = validate_quantity!(quantity, allow_zero: true)

      if quantity.zero?
        items.delete(product.id)
      else
        validate_stock!(product, quantity)
        items[product.id] = quantity
      end
      self
    end

    def remove(product_id)
      product = find_product!(product_id)
      ensure_present!(product)
      items.delete(product.id)
      self
    end

    def empty?
      items.empty?
    end

    def item_count
      items.values.sum
    end

    def subtotal_cents
      lines.sum(&:subtotal_cents)
    end

    def shipping_cents
      return 0 if empty? || subtotal_cents >= FREE_SHIPPING_THRESHOLD_CENTS

      SHIPPING_CENTS
    end

    def total_cents
      subtotal_cents + shipping_cents
    end

    def free_shipping_remaining_cents
      [ FREE_SHIPPING_THRESHOLD_CENTS - subtotal_cents, 0 ].max
    end

    def to_session
      items.transform_values(&:to_i)
    end

    private

    def normalize(raw_items)
      return {} unless raw_items.is_a?(Hash)

      raw_items.each_with_object({}) do |(product_id, raw_quantity), normalized|
        product = @catalog.find(product_id)
        quantity = strict_integer(raw_quantity)
        next unless product&.in_stock? && quantity&.positive?

        normalized[product.id] = [ quantity, product.stock, MAX_QUANTITY ].min
      end
    end

    def find_product!(product_id)
      @catalog.find(product_id) || raise(InvalidOperation, "That product is no longer available.")
    end

    def find_available_product!(product_id)
      product = find_product!(product_id)
      raise InvalidOperation, "#{product.name} is currently sold out." unless product.in_stock?

      product
    end

    def ensure_present!(product)
      return if items.key?(product.id)

      raise InvalidOperation, "#{product.name} is not in your bag."
    end

    def validate_quantity!(raw_quantity, allow_zero: false)
      quantity = strict_integer(raw_quantity)
      minimum = allow_zero ? 0 : 1
      unless quantity&.between?(minimum, MAX_QUANTITY)
        raise InvalidOperation, "Choose a quantity between #{minimum} and #{MAX_QUANTITY}."
      end

      quantity
    end

    def validate_stock!(product, quantity)
      return if quantity <= product.stock && quantity <= MAX_QUANTITY

      raise InvalidOperation, "Only #{[ product.stock, MAX_QUANTITY ].min} of #{product.name} can be added."
    end

    def strict_integer(value)
      string = value.to_s
      return unless /\A\d{1,2}\z/.match?(string)

      string.to_i
    end
  end
end
