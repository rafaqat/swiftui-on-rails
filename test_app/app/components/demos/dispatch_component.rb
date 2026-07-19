# frozen_string_literal: true

module Demos
  # Dispatch uses the DSL's privacy-preserving schematic map. Station
  # selection is URL state, so detail remains server-rendered and shareable.
  class DispatchComponent < ApplicationComponent
    STATUS_STYLES = {
      "online" => "bg-emerald-100 text-emerald-800",
      "degraded" => "bg-amber-100 text-amber-800",
      "offline" => "bg-slate-200 text-slate-600"
    }.freeze

    prop :stations, type: Array, required: true
    prop :selected, type: Object, default: nil

    swift_ui do
      component = @component

      grid(columns: 2, spacing: 16) do
        # ── Server-rendered schematic map ──────────────
        div do
          hstack(spacing: 8, alignment: :center) do
            text("Network map").tw("text-xs font-black uppercase tracking-widest text-slate-400")
          end.tw("relative z-10")

          # The transform target must sit inside a separate clipping wrapper:
          # overflow-hidden on the scaled element itself does not clip its
          # own transform, and the scaled SVG would cover the controls.
          div do
            div do
              map(
                center: Demos::DispatchNetwork::CENTER,
                span: Demos::DispatchNetwork::SPAN,
                label: "Dispatch station network",
                markers: component.stations.map do |station|
                  map_marker(latitude: station.latitude, longitude: station.longitude, label: station.name)
                end
              )
            end.tw("origin-center")
          end.tw("relative z-0 mt-3 overflow-hidden rounded-2xl")
        end
          .tw("overflow-hidden rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")

        # ── Stations + URL-driven detail ───────────────
        vstack(spacing: 8, alignment: :start) do
          text("Stations").tw("text-xs font-black uppercase tracking-widest text-slate-400")

          component.stations.each do |station|
            station_row(station, component.selected&.id == station.id)
          end

          if component.selected
            vstack(spacing: 8, alignment: :start) do
              hstack(spacing: 8, alignment: :center) do
                text(component.selected.name).tw("text-lg font-black text-slate-950")
                span(component.selected.status.capitalize)
                  .tw("rounded-full px-3 py-1 text-xs font-black uppercase tracking-widest #{STATUS_STYLES.fetch(component.selected.status)}")
              end
              text(component.selected.detail).tw("text-sm font-medium leading-6 text-slate-600")
              a("Clear selection", href: helpers.demos_dispatch_path)
                .tw("text-sm font-black text-slate-400 transition hover:text-slate-950")
            end
              .tw("mt-4 w-full rounded-2xl bg-white p-5 ring-1 ring-slate-900/10")
              .data(dispatch_detail: component.selected.id)
          else
            text("Select a station to inspect its live detail.")
              .tw("mt-4 text-sm font-medium text-slate-500")
          end
        end
          .tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")
      end
    end

    private

    def station_row(station, active)
      a(
        href: helpers.demos_dispatch_path(station: station.id),
        data: { dispatch_station: station.id }
      ) do
        hstack(spacing: 8, alignment: :center) do
          span("").tw("h-2.5 w-2.5 rounded-full #{station.status == 'online' ? 'bg-emerald-500' : station.status == 'degraded' ? 'bg-amber-500' : 'bg-slate-400'}")
          text(station.name).tw("text-sm font-bold #{active ? 'text-white' : 'text-slate-950'}")
          spacer
          icon("chevron_right", size: 12).tw(active ? "text-white/70" : "text-slate-300")
        end
      end.tw("block w-full rounded-2xl px-4 py-3 transition #{active ? 'bg-slate-950' : 'bg-slate-50 hover:bg-slate-100'}")
    end
  end
end
