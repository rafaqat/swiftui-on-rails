# frozen_string_literal: true

module Demos
  # Session-backed kanban board state. The server owns card order — drags are
  # optimistic in the DOM, but this object is the source of truth and every
  # move is validated here. Invalid cards, columns, positions, or WIP
  # violations raise; the controller maps those to bounded error responses.
  class FlightplanState
    class WipLimitError < ArgumentError; end

    COLUMNS = {
      "backlog" => "Backlog",
      "in_flight" => "In Flight",
      "landed" => "Landed"
    }.freeze

    WIP_LIMITS = { "in_flight" => 4 }.freeze

    CARDS = {
      "orbit-nav" => { title: "Orbital navigation pass", tag: "guidance", priority: "high" },
      "fuel-audit" => { title: "Fuel margin audit", tag: "systems", priority: "medium" },
      "crew-brief" => { title: "Crew launch brief", tag: "ops", priority: "medium" },
      "telemetry-cal" => { title: "Telemetry calibration", tag: "systems", priority: "high" },
      "range-safety" => { title: "Range safety sign-off", tag: "ops", priority: "high" },
      "comms-check" => { title: "Deep-space comms check", tag: "comms", priority: "low" },
      "landing-sim" => { title: "Landing simulation run", tag: "guidance", priority: "medium" },
      "weather-hold" => { title: "Weather hold review", tag: "ops", priority: "low" },
      "payload-seal" => { title: "Payload bay seal test", tag: "systems", priority: "medium" }
    }.freeze

    DEFAULT_ORDER = {
      "backlog" => %w[orbit-nav fuel-audit crew-brief telemetry-cal],
      "in_flight" => %w[range-safety comms-check landing-sim],
      "landed" => %w[weather-hold payload-seal]
    }.freeze

    def initialize(stored = nil)
      @order = normalize(stored)
    end

    def to_h
      @order.transform_values(&:dup)
    end

    # Column view models for the board component.
    def columns
      COLUMNS.map do |id, name|
        {
          id: id,
          name: name,
          wip_limit: WIP_LIMITS[id],
          cards: @order.fetch(id).map { |key| CARDS.fetch(key).merge(key: key) }
        }
      end
    end

    def move!(card:, to:, position: nil)
      card = card.to_s
      to = to.to_s
      raise ArgumentError, "unknown card" unless CARDS.key?(card)
      raise ArgumentError, "unknown column" unless COLUMNS.key?(to)

      from = column_of(card)
      limit = WIP_LIMITS[to]
      if limit && from != to && @order.fetch(to).length >= limit
        raise WipLimitError, "#{COLUMNS.fetch(to)} is at its limit of #{limit} cards"
      end

      @order.fetch(from).delete(card)
      destination = @order.fetch(to)
      index = clamp_position(position, destination.length)
      destination.insert(index, card)
      self
    end

    def reset!
      @order = deep_dup(DEFAULT_ORDER)
      self
    end

    private

    def column_of(card)
      @order.each { |column, keys| return column if keys.include?(card) }
      raise ArgumentError, "card is not on the board"
    end

    def clamp_position(position, length)
      return length if position.nil? || position.to_s.empty?

      Integer(position.to_s, exception: false)&.clamp(0, length) ||
        raise(ArgumentError, "invalid position")
    end

    # Session data is user-influenced input: rebuild from defaults unless the
    # stored value is exactly a permutation of the known cards.
    def normalize(stored)
      return deep_dup(DEFAULT_ORDER) unless stored.is_a?(Hash)

      candidate = COLUMNS.keys.to_h do |column|
        keys = Array(stored[column] || stored[column.to_sym]).map(&:to_s)
        [column, keys]
      end
      all_keys = candidate.values.flatten
      return deep_dup(DEFAULT_ORDER) unless all_keys.sort == CARDS.keys.sort

      candidate
    end

    def deep_dup(order)
      order.transform_values(&:dup)
    end
  end
end
