# frozen_string_literal: true

module Demos
  # Deterministic in-memory dataset for the Ledger demo: 500 invoices built
  # from a fixed seed and a fixed base date, so every test run and every
  # visitor sees identical data without a database table.
  class LedgerDataset
    Row = Data.define(:id, :customer, :status, :amount_cents, :issued_on) do
      def amount
        format("$%.2f", amount_cents / 100.0)
      end
    end

    STATUSES = %w[draft pending paid overdue].freeze
    BASE_DATE = Date.new(2026, 1, 1)

    CUSTOMERS = [
      "Acme Corp", "Globex", "Initech", "Umbrella Labs", "Stark Industries",
      "Wayne Enterprises", "Wonka Works", "Tyrell Corp", "Cyberdyne Systems",
      "Aperture Science", "Soylent Co", "Hooli", "Pied Piper", "Massive Dynamic",
      "Oscorp", "Gringotts", "Duff Brewing", "Vandelay Industries",
      "Bluth Company", "Dunder Mifflin"
    ].freeze

    class << self
      def rows
        @rows ||= build_rows.freeze
      end

      private

      def build_rows
        random = Random.new(4242)
        (1..500).map do |index|
          Row.new(
            id: format("INV-%04d", index),
            customer: CUSTOMERS[random.rand(CUSTOMERS.length)],
            status: STATUSES[random.rand(STATUSES.length)],
            amount_cents: (random.rand(25_00..9_999_99) / 25) * 25,
            issued_on: BASE_DATE - random.rand(0..365)
          )
        end
      end
    end
  end
end
