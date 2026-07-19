# frozen_string_literal: true

# A dashboard stat tile: label, headline value, and a delta with direction.
# Used by the Pulse demo and standalone in the storybook.
class StatCardComponent < ApplicationComponent
  TREND_STYLES = {
    "up" => { classes: "bg-emerald-100 text-emerald-800", glyph: "arrow_up" },
    "down" => { classes: "bg-rose-100 text-rose-800", glyph: "arrow_down" },
    "flat" => { classes: "bg-slate-100 text-slate-600", glyph: "minus" }
  }.freeze

  prop :stat_label, type: String, required: true
  prop :value, type: String, required: true
  prop :delta, type: String, default: nil
  prop :trend, type: String, default: "flat"
  prop :detail, type: String, default: nil

  swift_ui do
    style = TREND_STYLES.fetch(trend, TREND_STYLES["flat"])

    vstack(spacing: 8, alignment: :start) do
      text(stat_label).tw("text-xs font-black uppercase tracking-widest text-slate-400")

      hstack(spacing: 8, alignment: :center) do
        text(value).tw("text-3xl font-black tracking-tight text-slate-950")
        if delta
          hstack(spacing: 4, alignment: :center) do
            icon(style.fetch(:glyph), size: 10)
            text(delta).tw("text-xs font-black")
          end.tw("rounded-full px-2 py-1 #{style.fetch(:classes)}")
        end
      end

      text(detail).tw("text-xs font-bold text-slate-500") if detail
    end
      .tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")
  end
end
