# frozen_string_literal: true

module Demos
  # Deterministic simulated telemetry for the Pulse dashboard. Every value is
  # a pure function of (range, tick), so tests are stable, ticks always
  # change something visible, and no background process is required.
  class PulseTelemetry
    RANGES = {
      "1h" => { label: "Last hour", points: 12, step_label: "5m" },
      "24h" => { label: "Last 24 hours", points: 24, step_label: "1h" },
      "7d" => { label: "Last 7 days", points: 14, step_label: "12h" }
    }.freeze

    Snapshot = Data.define(
      :range, :tick, :throughput_series, :requests_per_minute, :requests_delta,
      :p95_latency_ms, :latency_delta, :error_rate_percent, :error_delta,
      :active_regions, :region_rollout, :services
    )

    class << self
      def normalize_range(candidate)
        RANGES.key?(candidate.to_s) ? candidate.to_s : "24h"
      end

      def normalize_tick(candidate)
        Integer(candidate.to_s, exception: false)&.clamp(0, 1_000_000) || 0
      end

      def snapshot(range:, tick: 0)
        range = normalize_range(range)
        tick = normalize_tick(tick)
        config = RANGES.fetch(range)

        series = build_series(range, tick, config.fetch(:points))
        current = series.values.last
        previous = series.values[-2] || current

        Snapshot.new(
          range: range,
          tick: tick,
          throughput_series: series,
          requests_per_minute: current,
          requests_delta: percent_delta(current, previous),
          p95_latency_ms: 140 + wave(tick, period: 9, amplitude: 55),
          latency_delta: percent_delta(140 + wave(tick, period: 9, amplitude: 55),
                                       140 + wave(tick - 1, period: 9, amplitude: 55)),
          error_rate_percent: (0.4 + wave(tick, period: 13, amplitude: 0.35, phase: 2)).round(2),
          error_delta: percent_delta(0.4 + wave(tick, period: 13, amplitude: 0.35, phase: 2),
                                     0.4 + wave(tick - 1, period: 13, amplitude: 0.35, phase: 2)),
          active_regions: 5 + ((tick / 7) % 3),
          region_rollout: 62 + wave(tick, period: 17, amplitude: 20).round,
          services: service_rows(tick)
        )
      end

      private

      def build_series(range, tick, points)
        seed = range.each_byte.sum
        (0...points).to_h do |index|
          position = index + tick
          value = 900 +
                  (Math.sin((position + seed) / 3.2) * 220) +
                  (Math.cos((position + seed) / 7.1) * 140) +
                  (index * 6)
          ["T#{index + 1}", value.round]
        end
      end

      def wave(tick, period:, amplitude:, phase: 0)
        (Math.sin(((tick + phase) * 2 * Math::PI) / period) * amplitude).round(2)
      end

      def percent_delta(current, previous)
        return 0.0 if previous.to_f.zero?

        (((current - previous) / previous.to_f) * 100).round(1)
      end

      def service_rows(tick)
        [
          { name: "API gateway", health: 88 + wave(tick, period: 11, amplitude: 10).round },
          { name: "Checkout", health: 76 + wave(tick, period: 7, amplitude: 18, phase: 3).round },
          { name: "Search", health: 92 + wave(tick, period: 5, amplitude: 6, phase: 1).round },
          { name: "Notifications", health: 68 + wave(tick, period: 15, amplitude: 22, phase: 5).round }
        ].map { |row| row.merge(health: row[:health].clamp(1, 100)) }
      end
    end
  end
end
