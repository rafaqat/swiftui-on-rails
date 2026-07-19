# frozen_string_literal: true

# Atlas Command is a native disclosure over server-rendered navigation links.
# The semantic popover contract supplies keyboard and outside-click behavior;
# application code owns only Ruby data and Rails destinations.
class CommandPaletteComponent < ApplicationComponent
  # Storybook preview fixture — the app always passes real commands.
  SAMPLE_COMMANDS = [
    { label: "Ledger", href: "#ledger", section: "Data", keywords: "invoices table url" },
    { label: "Flightplan", href: "#flightplan", section: "Boards", keywords: "kanban drag drop" },
    { label: "Pulse", href: "#pulse", section: "Data", keywords: "dashboard telemetry live" },
    { label: "Component lab", href: "#lab", section: "Navigate", keywords: "storybook stories" }
  ].freeze

  prop :commands, type: Array, default: -> { SAMPLE_COMMANDS }
  prop :placeholder, type: String, default: "Search demos, labs, and pages…"
  prop :hint, type: String, default: "Jump anywhere"

  swift_ui do
    popover(hint, id: "command-palette") do
      vstack(spacing: 8, alignment: :stretch) do
        text(placeholder).tw("px-4 pt-3 text-xs font-black uppercase tracking-widest text-slate-400")
        scroll_view do
          list(aria: { label: "Commands" }) do
            commands.each do |command|
              list_item(data: { command_keywords: command[:keywords].to_s }) do
                a(href: command.fetch(:href)) do
                  hstack(spacing: 8, alignment: :center) do
                    span(command.fetch(:section)).tw("w-24 shrink-0 text-xs font-black uppercase tracking-widest text-slate-400")
                    text(command.fetch(:label)).tw("text-sm font-bold text-slate-950")
                    spacer
                    icon("arrow_right", size: 12).tw("text-slate-300")
                  end
                end.tw("block rounded-xl px-4 py-3 transition hover:bg-slate-100")
              end
            end
          end.tw("p-2")
        end.tw("max-h-80")
      end
    end
      .tw("relative rounded-2xl bg-white shadow ring-1 ring-slate-900/10")
  end
end
