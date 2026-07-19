# frozen_string_literal: true

module Demos
  # The Pulse analytics board. Time range and tick are URL state and every
  # chart is regenerated as accessible server SVG.
  class PulseComponent < ApplicationComponent
    prop :snapshot, type: Object, required: true

    swift_ui do
      component = @component
      snapshot = component.snapshot

      div(id: "pulse-board", data: { pulse_tick: snapshot.tick }) do
        vstack(spacing: 16, alignment: :start) do
          hstack(spacing: 8, alignment: :center) do
            Demos::PulseTelemetry::RANGES.each do |range_key, config|
              range_chip(range_key, config.fetch(:label), snapshot.range == range_key)
            end
            spacer
            hstack(spacing: 4, alignment: :center) do
              span("").tw("h-2 w-2 animate-pulse rounded-full bg-emerald-500")
              text("Live · tick #{snapshot.tick}")
                .tw("text-xs font-black uppercase tracking-widest text-slate-400")
                .data(pulse_status: true)
            end

            a("Refresh", href: component.next_tick_path)
              .tw("rounded-full bg-white px-4 py-2 text-xs font-black text-slate-600 ring-1 ring-slate-900/10 hover:bg-slate-100")
          end

          grid(columns: 4, spacing: 12) do
            render StatCardComponent.new(
              stat_label: "Requests / min",
              value: snapshot.requests_per_minute.to_s,
              delta: component.format_delta(snapshot.requests_delta),
              trend: component.trend_for(snapshot.requests_delta),
              detail: Demos::PulseTelemetry::RANGES.fetch(snapshot.range).fetch(:label)
            )
            render StatCardComponent.new(
              stat_label: "P95 latency",
              value: "#{snapshot.p95_latency_ms.round} ms",
              delta: component.format_delta(snapshot.latency_delta),
              trend: component.trend_for(snapshot.latency_delta, invert: true),
              detail: "Across all regions"
            )
            render StatCardComponent.new(
              stat_label: "Error rate",
              value: "#{snapshot.error_rate_percent}%",
              delta: component.format_delta(snapshot.error_delta),
              trend: component.trend_for(snapshot.error_delta, invert: true),
              detail: "5xx responses"
            )
            render StatCardComponent.new(
              stat_label: "Active regions",
              value: snapshot.active_regions.to_s,
              trend: "flat",
              detail: "Rollout #{snapshot.region_rollout}%"
            )
          end

          grid(columns: 2, spacing: 16) do
            div do
              chart(
                snapshot.throughput_series,
                type: :line,
                title: "Throughput",
                description: "Requests per minute across the selected window",
                color: :blue
              )
            end.tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")

            vstack(spacing: 12, alignment: :start) do
              text("Service health").tw("text-xs font-black uppercase tracking-widest text-slate-400")
              snapshot.services.each do |service|
                vstack(spacing: 4, alignment: :start) do
                  hstack(spacing: 8, alignment: :center) do
                    text(service[:name]).tw("text-sm font-bold text-slate-950")
                    spacer
                    text("#{service[:health]}%").tw("text-xs font-black text-slate-500")
                  end
                  progress_view(value: service[:health], total: 100, label: "#{service[:name]} health")
                    .tw("w-full")
                end.tw("w-full")
              end

              divider

              hstack(spacing: 12, alignment: :center) do
                gauge(
                  value: snapshot.region_rollout,
                  range: 0..100,
                  label: "Region rollout percent"
                ).tw("w-full")
              end
            end.tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")
          end
        end
      end
    end

    def range_chip(range_key, label, active)
      chip = a(label, href: helpers.demos_pulse_path(range: range_key))
        .tw(
          "rounded-full px-4 py-2 text-sm font-black transition " +
          (active ? "bg-slate-950 text-white" : "bg-white text-slate-600 ring-1 ring-slate-900/10 hover:bg-slate-100")
        )
      chip.attr("aria-current", "page") if active
      chip
    end

    def next_tick_path
      helpers.demos_pulse_path(range: snapshot.range, tick: snapshot.tick + 1)
    end

    def format_delta(delta)
      "#{delta.positive? ? '+' : ''}#{delta}%"
    end

    def trend_for(delta, invert: false)
      return "flat" if delta.zero?

      positive_is_good = !invert
      if delta.positive?
        positive_is_good ? "up" : "down"
      else
        positive_is_good ? "down" : "up"
      end
    end
  end
end
