# frozen_string_literal: true

# Gallery card for one DemoCatalog entry. Rendered as a collection on /demos:
#   DemoCardComponent.with_collection(demos)
class DemoCardComponent < ApplicationComponent
  MODEL_BADGE_CLASSES = {
    url: "bg-rose-100 text-rose-800",
    turbo: "bg-blue-100 text-blue-800",
    cable: "bg-teal-100 text-teal-800",
    reactive: "bg-violet-100 text-violet-800"
  }.freeze

  with_collection_parameter :demo

  prop :demo, type: Hash, required: true

  # ViewComponent's collection rendering validates that the collection
  # parameter appears in the initializer signature; the SwiftUI Rails prop
  # system uses a **props catch-all, so surface the keyword explicitly.
  def initialize(demo:, demo_counter: nil, **rest)
    super(demo: demo, **rest)
  end

  swift_ui do
    a(href: demo_path, data: { demo_card: demo[:slug] })
      .tw("group relative flex h-full flex-col overflow-hidden rounded-3xl bg-white p-6 shadow-lg ring-1 ring-slate-900/10 transition hover:-translate-y-1 hover:shadow-2xl") do
      div.tw("h-1.5 w-16 rounded-full bg-gradient-to-r #{demo[:accent]}")

      hstack(spacing: 2) do
        span(DemoCatalog.model_label(demo[:model]))
          .tw("rounded-full px-3 py-1 text-xs font-black uppercase tracking-widest #{MODEL_BADGE_CLASSES.fetch(demo[:model])}")
        spacer
        span("↗").tw("text-2xl transition group-hover:translate-x-1")
      end.tw("mt-5")

      text(demo[:name])
        .tw("mt-4 text-2xl font-black tracking-tight text-slate-950")

      text(demo[:description])
        .tw("mt-3 text-sm leading-6 text-slate-600")

      hstack(spacing: 2) do
        span(demo[:category]).tw("text-xs font-bold uppercase tracking-widest text-slate-400")
        spacer
        span("Launch demo →").tw("text-sm font-black text-slate-950")
      end.tw("mt-auto pt-6")
    end
  end

  private

  def demo_path
    DemoCatalog.path_for(demo, helpers)
  end
end
