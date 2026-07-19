# frozen_string_literal: true

require "securerandom"

module Showcase
  class Checkout
    EMAIL_PATTERN = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    MAX_LENGTHS = { name: 80, email: 120, address: 240 }.freeze

    attr_reader :name, :email, :address, :errors

    def initialize(attributes = {})
      values = attributes.to_h.with_indifferent_access
      @name = normalize(values[:name], MAX_LENGTHS[:name])
      @email = normalize(values[:email], MAX_LENGTHS[:email])
      @address = normalize(values[:address], MAX_LENGTHS[:address])
      @errors = {}
    end

    def valid?
      errors.clear
      validate_length(:name, name, minimum: 2)
      validate_length(:email, email)
      add_error(:email, "Enter a valid email address.") if email.length <= MAX_LENGTHS[:email] && !EMAIL_PATTERN.match?(email)
      validate_length(:address, address, minimum: 10)
      errors.empty?
    end

    def place_order(cart)
      raise ArgumentError, "Cannot check out an empty cart" if cart.empty?
      raise ArgumentError, "Checkout details are invalid" unless valid?

      {
        reference: "SRV-#{SecureRandom.hex(3).upcase}",
        total_cents: cart.total_cents,
        item_count: cart.item_count,
        email: email
      }
    end

    private

    def normalize(value, maximum)
      value.to_s.strip.gsub(/\s+/, " ").first(maximum + 1)
    end

    def add_error(field, message)
      (errors[field] ||= []) << message
    end

    def validate_length(field, value, minimum: nil)
      if value.length > MAX_LENGTHS.fetch(field)
        add_error(field, "#{field.to_s.capitalize} is too long.")
      elsif minimum && value.length < minimum
        message = field == :address ? "Enter a complete delivery address." : "Enter your full name."
        add_error(field, message)
      end
    end
  end
end
