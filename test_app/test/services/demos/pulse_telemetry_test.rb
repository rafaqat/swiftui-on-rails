# frozen_string_literal: true

require "test_helper"

module Demos
  class PulseTelemetryTest < ActiveSupport::TestCase
    test "snapshots are deterministic for the same range and tick" do
      first = PulseTelemetry.snapshot(range: "24h", tick: 5)
      second = PulseTelemetry.snapshot(range: "24h", tick: 5)

      assert_equal first, second
    end

    test "consecutive ticks change the visible numbers" do
      current = PulseTelemetry.snapshot(range: "24h", tick: 5)
      next_tick = PulseTelemetry.snapshot(range: "24h", tick: 6)

      refute_equal current.throughput_series, next_tick.throughput_series
    end

    test "each range produces its configured number of points" do
      PulseTelemetry::RANGES.each do |range, config|
        snapshot = PulseTelemetry.snapshot(range: range)
        assert_equal config.fetch(:points), snapshot.throughput_series.length
      end
    end

    test "unknown ranges and hostile ticks normalize to safe defaults" do
      assert_equal "24h", PulseTelemetry.normalize_range("constantize")
      assert_equal 0, PulseTelemetry.normalize_tick("DROP TABLE")
      assert_equal 1_000_000, PulseTelemetry.normalize_tick("999999999999")

      snapshot = PulseTelemetry.snapshot(range: "<script>", tick: "-4")
      assert_equal "24h", snapshot.range
      assert_equal 0, snapshot.tick
    end

    test "service health stays within 1..100" do
      (0..40).each do |tick|
        PulseTelemetry.snapshot(range: "1h", tick: tick).services.each do |service|
          assert_includes 1..100, service[:health]
        end
      end
    end
  end
end
