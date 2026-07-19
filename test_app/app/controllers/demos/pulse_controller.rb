# frozen_string_literal: true

module Demos
  # Pulse: the time-range is URL state; the live tick is a polled GET that
  # returns a Turbo Stream replacing the whole board. All chart SVG is
  # regenerated server-side per tick.
  class PulseController < BaseController
    def show
      @snapshot = Demos::PulseTelemetry.snapshot(
        range: params[:range],
        tick: Demos::PulseTelemetry.normalize_tick(params[:tick])
      )
    end

    def tick
      snapshot = Demos::PulseTelemetry.snapshot(
        range: params[:range],
        tick: Demos::PulseTelemetry.normalize_tick(params[:tick]) + 1
      )

      render turbo_stream: turbo_stream.replace(
        "pulse-board",
        Demos::PulseComponent.new(snapshot: snapshot)
      )
    end
  end
end
