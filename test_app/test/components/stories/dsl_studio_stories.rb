# frozen_string_literal: true

# The storybook's flagship interactive story: 21 live controls composing a
# complete page — navigation bar, hero, feature card grid, and signup form —
# from DSL primitives alone.
class DslStudioStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  # Navigation
  control :nav_brand, as: :text, default: "Orbit"
  control :nav_links, as: :number, default: 3, min: 0, max: 5
  control :nav_dark, as: :boolean, default: true

  # Hero
  control :hero_title, as: :text, default: "Ship interfaces the Rails way"
  control :hero_subtitle, as: :text, default: "SwiftUI-inspired Ruby, rendered on the server."
  control :hero_gradient_from, as: :select,
          options: %w[sky-500 violet-600 emerald-500 amber-500 rose-500], default: "sky-500"
  control :hero_gradient_to, as: :select,
          options: %w[violet-600 blue-700 teal-700 orange-600 pink-600], default: "violet-600"
  control :show_cta, as: :boolean, default: true
  control :cta_text, as: :text, default: "Get started"
  control :cta_style, as: :select, options: %w[primary secondary danger ghost], default: "primary"

  # Feature grid
  control :grid_columns, as: :select, options: [2, 3, 4], default: 3
  control :card_count, as: :number, default: 6, min: 1, max: 9
  control :card_spacing, as: :select, options: [8, 12, 16, 24], default: 16
  control :card_rounded, as: :select, options: %w[md lg xl], default: "xl"
  control :show_badges, as: :boolean, default: true
  control :badge_tone, as: :select, options: %w[neutral info success warning danger], default: "success"

  # Signup form
  control :show_form, as: :boolean, default: true
  control :form_title, as: :text, default: "Join the beta"
  control :input_placeholder, as: :text, default: "you@example.com"
  control :submit_label, as: :text, default: "Request access"
  control :form_tint, as: :select, options: %w[slate-950 blue-600 emerald-600 violet-600], default: "slate-950"

  FEATURES = [
    ["Layouts", "vstack, hstack, zstack, and responsive grids"],
    ["Modifiers", "Chainable Tailwind styling on every element"],
    ["State", "Server-owned state with signed action round trips"],
    ["Navigation", "Route-first tabs, sheets, and toolbars"],
    ["Content", "Accessible charts, canvas, maps, and rich text"],
    ["Workflows", "Reordering, swipe actions, and documents"],
    ["Forms", "Native validation with progressive enhancement"],
    ["Collections", "ViewComponent 2.0 collection rendering"],
    ["Icons", "A curated decorative glyph vocabulary"]
  ].freeze

  def default(
    nav_brand: "Orbit", nav_links: 3, nav_dark: true,
    hero_title: "Ship interfaces the Rails way",
    hero_subtitle: "SwiftUI-inspired Ruby, rendered on the server.",
    hero_gradient_from: "sky-500", hero_gradient_to: "violet-600",
    show_cta: true, cta_text: "Get started", cta_style: "primary",
    grid_columns: 3, card_count: 6, card_spacing: 16, card_rounded: "xl",
    show_badges: true, badge_tone: "success",
    show_form: true, form_title: "Join the beta",
    input_placeholder: "you@example.com", submit_label: "Request access",
    form_tint: "slate-950"
  )
    features = FEATURES.first(card_count.to_i.clamp(1, FEATURES.length))

    content_tag(:div, class: "min-h-full bg-slate-50") do
      swift_ui do
        vstack(spacing: 0, alignment: :stretch) do
          # ── Navigation bar ─────────────────────────────
          hstack(spacing: 16, alignment: :center) do
            text(nav_brand).tw("text-lg font-black #{nav_dark ? 'text-white' : 'text-slate-950'}")
            spacer
            nav_links.to_i.clamp(0, 5).times do |index|
              text("Link #{index + 1}")
                .tw("text-sm font-bold #{nav_dark ? 'text-white/70 hover:text-white' : 'text-slate-500 hover:text-slate-950'} cursor-pointer")
            end
          end.tw("px-8 py-4 #{nav_dark ? 'bg-slate-950' : 'bg-white border-b border-slate-200'}")

          # ── Hero ───────────────────────────────────────
          vstack(spacing: 12, alignment: :center) do
            text(hero_title).tw("max-w-2xl text-center text-4xl font-black tracking-tight text-white")
            text(hero_subtitle).tw("max-w-xl text-center text-lg font-medium text-white/80")
            if show_cta
              button(cta_text)
                .button_style(cta_style.to_sym)
                .tw("mt-2")
            end
          end.tw("bg-gradient-to-br from-#{hero_gradient_from} to-#{hero_gradient_to} px-8 py-16")

          # ── Feature grid ───────────────────────────────
          div do
            grid(columns: grid_columns.to_i, spacing: card_spacing.to_i) do
              features.each do |title, description|
                vstack(spacing: 8, alignment: :start) do
                  hstack(spacing: 8, alignment: :center) do
                    text(title).tw("text-base font-black text-slate-950")
                    spacer
                    badge("DSL", tone: badge_tone.to_sym) if show_badges
                  end
                  text(description).tw("text-sm font-medium leading-6 text-slate-500")
                end
                  .tw("bg-white p-5 shadow ring-1 ring-slate-900/5")
                  .rounded(card_rounded)
              end
            end
          end.tw("px-8 py-10")

          # ── Signup form ────────────────────────────────
          if show_form
            vstack(spacing: 12, alignment: :center) do
              text(form_title).tw("text-2xl font-black text-slate-950")
              hstack(spacing: 8, alignment: :center) do
                input(type: "email", placeholder: input_placeholder, aria: { label: "Email address" })
                  .tw("w-72 rounded-full border border-slate-300 bg-white px-5 py-3 text-sm font-medium focus:outline-none")
                button(submit_label)
                  .tw("rounded-full bg-#{form_tint} px-6 py-3 text-sm font-black text-white transition hover:opacity-90")
              end
            end.tw("border-t border-slate-200 bg-white px-8 py-12")
          end
        end
      end
    end
  end
end
