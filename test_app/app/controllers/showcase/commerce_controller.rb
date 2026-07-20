# frozen_string_literal: true

module Showcase
  class CommerceController < ApplicationController
    MAX_QUERY_LENGTH = 80

    before_action :load_cart

    def show
      load_catalog_state
      @checkout = Checkout.new
      @order = flash[:showcase_order]
    end

    def product
      @product = @catalog.find(params[:id].to_s)
      return render plain: "Product not found", status: :not_found unless @product

      @checkout = Checkout.new
      @quick_view = turbo_frame_request?
    end

    def add_to_cart
      values = params.permit(:product_id, :quantity)
      product = @catalog.find(values[:product_id].to_s)
      return respond_with_error("That product could not be found.") unless product

      @cart.add(values[:product_id], values[:quantity].presence || 1)
      persist_cart

      respond_with_cart(message: "#{product.name} was added to your bag.")
    rescue Cart::InvalidOperation => error
      respond_with_error(error.message)
    end

    def update_cart
      values = params.permit(:quantity)
      @cart.update(params[:id].to_s, values[:quantity])
      persist_cart

      respond_with_cart(message: "Your bag was updated.")
    rescue Cart::InvalidOperation => error
      respond_with_error(error.message)
    end

    def remove_from_cart
      product = @catalog.find(params[:id].to_s)
      return respond_with_error("That product could not be found.") unless product

      @cart.remove(params[:id].to_s)
      persist_cart

      respond_with_cart(message: "#{product.name} was removed from your bag.")
    rescue Cart::InvalidOperation => error
      respond_with_error(error.message)
    end

    def checkout
      @checkout = Checkout.new(checkout_params)
      if @cart.empty?
        @checkout.errors.add(:base, "Your bag is empty. Add something before checking out.")
        return respond_with_checkout_error
      end

      unless @checkout.valid?
        return respond_with_checkout_error
      end

      @order = @checkout.place_order(@cart)
      @cart = Cart.new({}, catalog: @catalog)
      persist_cart

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            cart_stream,
            checkout_stream(success: @order),
            nav_count_stream,
            notice_stream("Order #{@order[:reference]} is confirmed.", tone: :success)
          ]
        end
        format.html do
          flash[:showcase_order] = @order
          redirect_to showcase_commerce_path,
            status: :see_other,
            notice: "Order #{@order[:reference]} is confirmed."
        end
      end
    end

    private

    def load_cart
      @catalog = Catalog.new
      @cart = Cart.new(session[:showcase_commerce_cart], catalog: @catalog)
      persist_cart
    end

    def persist_cart
      session[:showcase_commerce_cart] = @cart.to_session
    end

    def load_catalog_state
      values = params.permit(:q, :category, :max_price, :in_stock, :sort)
      @query = values[:q].to_s.strip.first(MAX_QUERY_LENGTH)
      @category = values[:category].to_s
      @category = nil unless @catalog.categories.key?(@category)
      @max_price_cents = allowed_price_cap(values[:max_price])
      @in_stock = values[:in_stock].to_s == "1"
      @sort = values[:sort].to_s
      @sort = "featured" unless Catalog::SORTS.key?(@sort)
      @products = @catalog.search(
        query: @query,
        category: @category,
        max_price_cents: @max_price_cents,
        in_stock: @in_stock,
        sort: @sort
      )
    end

    def allowed_price_cap(value)
      string = value.to_s
      return unless /\A\d{1,6}\z/.match?(string)

      price = string.to_i
      price if Catalog::PRICE_CAPS.key?(price)
    end

    def checkout_params
      params.fetch(:checkout, ActionController::Parameters.new).permit(:name, :email, :address)
    end

    def respond_with_cart(message:)
      @checkout = Checkout.new
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            cart_stream,
            checkout_stream,
            nav_count_stream,
            turbo_stream.update("commerce_quick_view", ""),
            notice_stream(message, tone: :success)
          ]
        end
        format.html { redirect_to showcase_commerce_path, status: :see_other, notice: message }
      end
    end

    def respond_with_error(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: notice_stream(message, tone: :error), status: :unprocessable_entity
        end
        format.html { redirect_to showcase_commerce_path, status: :see_other, alert: message }
      end
    end

    def respond_with_checkout_error
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            checkout_stream,
            notice_stream("Please review the checkout details.", tone: :error)
          ], status: :unprocessable_entity
        end
        format.html do
          load_catalog_state
          render :show, status: :unprocessable_entity
        end
      end
    end

    def cart_stream
      turbo_stream.replace(
        "commerce_cart",
        partial: "showcase/commerce/cart",
        locals: { cart: @cart }
      )
    end

    def checkout_stream(success: nil)
      turbo_stream.replace(
        "commerce_checkout",
        partial: "showcase/commerce/checkout",
        locals: { cart: @cart, checkout: @checkout, success: success }
      )
    end

    def notice_stream(message, tone:)
      turbo_stream.update(
        "commerce_notice",
        partial: "showcase/commerce/notice",
        locals: { message: message, tone: tone }
      )
    end

    def nav_count_stream
      turbo_stream.update("commerce_nav_count", @cart.item_count)
    end
  end
end
