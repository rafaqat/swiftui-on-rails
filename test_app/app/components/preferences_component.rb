# frozen_string_literal: true

# The Preferences demo: the reactive layer's flagship. Server-owned `state`
# drives every visual in the preview pane; `binding` carries the slider value
# both ways; each button is a signed server action round trip (no bespoke
# JavaScript). The component must be listed in `config.allowed_components`
# for action restoration to run.
class PreferencesComponent < SwiftUIRails::Component::Base
  THEMES = {
    "aurora" => { label: "Aurora", classes: "from-sky-500 via-blue-600 to-violet-600" },
    "ember" => { label: "Ember", classes: "from-amber-400 via-orange-500 to-rose-600" },
    "moss" => { label: "Moss", classes: "from-lime-400 via-emerald-500 to-teal-700" }
  }.freeze

  DENSITY_PADDING = { 1 => "p-3", 2 => "p-6", 3 => "p-10" }.freeze
  DENSITY_LABELS = { 1 => "Compact", 2 => "Comfortable", 3 => "Spacious" }.freeze

  prop :panel_title, type: String, default: "Workspace preferences"

  state :theme, "aurora", type: String
  state :density, 2, type: Integer
  state :show_badges, true

  binding :accent, type: Integer, default: 60

  swift_ui do
    component = @component

    grid(columns: 2, spacing: 16) do
      # ── Controls ────────────────────────────────────────────────
      vstack(spacing: 16, alignment: :start) do
        text(component.panel_title).tw("text-lg font-black text-slate-950")

        vstack(spacing: 8, alignment: :start) do
          text("Theme").tw("text-xs font-black uppercase tracking-widest text-slate-400")
          control_group(label: "Theme") do
            THEMES.each do |key, config|
              theme_button = button(config.fetch(:label))
                .tw(
                  "rounded-full px-4 py-2 text-sm font-black transition " +
                  (component.theme == key ? "bg-slate-950 text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-200")
                )
              theme_button.on_click { component.theme = key }
            end
          end
        end

        vstack(spacing: 8, alignment: :start) do
          text("Density").tw("text-xs font-black uppercase tracking-widest text-slate-400")
          control_group(label: "Density") do
            decrease = button("−", aria: { label: "Decrease density" })
              .tw("rounded-full bg-slate-100 px-4 py-2 text-sm font-black text-slate-700 hover:bg-slate-200")
            decrease.on_click { component.density = [component.density - 1, 1].max }

            text(DENSITY_LABELS.fetch(component.density))
              .tw("min-w-28 text-center text-sm font-black text-slate-950")
              .data(preferences_density: true)

            increase = button("+", aria: { label: "Increase density" })
              .tw("rounded-full bg-slate-100 px-4 py-2 text-sm font-black text-slate-700 hover:bg-slate-200")
            increase.on_click { component.density = [component.density + 1, 3].min }
          end
        end

        vstack(spacing: 8, alignment: :start) do
          text("Badges").tw("text-xs font-black uppercase tracking-widest text-slate-400")
          badge_toggle = button(component.show_badges ? "Hide status badges" : "Show status badges")
            .tw("rounded-full bg-slate-100 px-4 py-2 text-sm font-black text-slate-700 hover:bg-slate-200")
          badge_toggle.on_click { component.show_badges = !component.show_badges }
        end

        vstack(spacing: 8, alignment: :start) do
          label("Accent intensity", for_input: "preferences-accent")
            .tw("text-xs font-black uppercase tracking-widest text-slate-400")
          input(
            id: "preferences-accent",
            type: "range",
            min: 0,
            max: 100,
            **component.accent.input_attributes
          ).tw("w-full")
        end
      end
        .tw("rounded-3xl bg-white p-6 shadow ring-1 ring-slate-900/10")

      # ── Live preview, restyled entirely from server state ───────
      vstack(spacing: 12, alignment: :start) do
        hstack(spacing: 8, alignment: :center) do
          text("Preview").tw("text-xs font-black uppercase tracking-widest text-white/70")
          spacer
          if component.show_badges
            span(THEMES.fetch(component.theme).fetch(:label))
              .tw("rounded-full bg-white/20 px-3 py-1 text-xs font-black uppercase tracking-widest text-white")
              .data(preferences_theme_badge: true)
          end
        end

        div do
          text("Orbit Dashboard").tw("text-2xl font-black text-white")
          text("Density: #{DENSITY_LABELS.fetch(component.density)} · Accent #{component.accent.value}%")
            .tw("mt-2 text-sm font-bold text-white/80")
        end
          .tw("w-full rounded-2xl bg-white/10 #{DENSITY_PADDING.fetch(component.density)}")

        if component.show_badges
          hstack(spacing: 8, alignment: :center) do
            span("Live").tw("rounded-full bg-emerald-400/90 px-3 py-1 text-xs font-black text-emerald-950")
            span("Synced").tw("rounded-full bg-white/20 px-3 py-1 text-xs font-black text-white")
          end
        end
      end
        .tw("rounded-3xl bg-gradient-to-br #{THEMES.fetch(component.theme).fetch(:classes)} p-6 shadow-xl")
        .style("opacity: #{(0.55 + (component.accent.value.to_i * 0.0045)).round(3)}")
    end
  end
end
