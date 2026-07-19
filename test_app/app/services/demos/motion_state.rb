# frozen_string_literal: true

module Demos
  # Session state for the Motion showcase: a counter for the numeric-pop
  # tile, a card order for the view-transition shuffle, and a reveal flag
  # for the staggered skeleton tile.
  class MotionState
    CARD_COUNT = 8
    CARD_ACCENTS = %w[
      from-sky-400 from-violet-500 from-emerald-400 from-amber-400
      from-rose-400 from-cyan-400 from-fuchsia-500 from-lime-400
    ].freeze

    def initialize(stored = nil)
      stored = {} unless stored.is_a?(Hash)
      @count = Integer(stored["count"].to_s, exception: false)&.clamp(0, 9999) || 0
      @order = normalize_order(stored["order"])
      @revealed = stored["revealed"] == true
    end

    attr_reader :count, :order

    def revealed?
      @revealed
    end

    def to_h
      { "count" => @count, "order" => @order, "revealed" => @revealed }
    end

    def bump!
      @count = [ @count + 1, 9999 ].min
      self
    end

    def shuffle!
      previous_order = @order
      @order = @order.shuffle
      @order = @order.rotate if @order == previous_order
      self
    end

    def toggle_reveal!
      @revealed = !@revealed
      self
    end

    def reset!
      @count = 0
      @order = normalize_order(nil)
      @revealed = false
      self
    end

    private

    def normalize_order(stored)
      candidate = Array(stored).map { |value| Integer(value.to_s, exception: false) }.compact
      candidate.sort == (1..CARD_COUNT).to_a ? candidate : (1..CARD_COUNT).to_a
    end
  end
end
