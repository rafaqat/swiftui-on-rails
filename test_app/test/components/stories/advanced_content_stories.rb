# frozen_string_literal: true

class AdvancedContentStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  def content_families
    swift_ui do
      div(class: "min-h-screen bg-slate-950 p-6 text-slate-100 sm:p-10") do
        div(class: "mx-auto max-w-6xl") do
          div(class: "mb-10 max-w-3xl") do
            text("WEB-NATIVE CONTENT").tw("text-xs font-black tracking-[0.3em] text-cyan-300")
            h1("Rich content without unsafe escape hatches", class: "mt-3 text-4xl font-black tracking-tight text-white sm:text-5xl")
            p(
              "Each view keeps the useful SwiftUI shape while exposing explicit browser, accessibility, caching, and security semantics.",
              class: "mt-4 text-lg leading-8 text-slate-300"
            )
          end

          div(class: "grid gap-6 lg:grid-cols-2") do
            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("AsyncImage", class: "text-xl font-black text-white")
              p("The native img owns decoding and HTTP caching; a declared RenderIR command reports its phase.", class: "mb-5 mt-2 text-sm text-slate-400")
              async_image(
                "/icon.svg",
                alt: "SwiftUI Rails gradient app mark",
                loading_label: "Loading app mark…",
                error_label: "App mark unavailable",
                id: "advanced-async-image",
                image_class: "mx-auto h-40 w-40 object-contain",
                class: "rounded-2xl bg-slate-900 p-5"
              )
            end

            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("Sanitized Rich Text", class: "text-xl font-black text-white")
              p("A fixed editorial allowlist preserves meaning without accepting styles, scripts, embeds, or event handlers.", class: "mb-5 mt-2 text-sm text-slate-400")
              rich_text(
                <<~HTML,
                  <h3>Release 2.0</h3>
                  <p>Advanced content is now <strong>accessible by default</strong> and safe for untrusted editorial input.</p>
                  <blockquote>Portable concepts get faithful semantics; browser-only behavior stays explicit.</blockquote>
                  <ul><li>Sanitized links</li><li>Structural headings</li><li>Code and lists</li></ul>
                  <p><a href="/rails/stories">Explore the component lab</a></p>
                HTML
                class: "rounded-2xl bg-slate-900 p-5 leading-7 text-slate-200"
              )
            end

            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("Accessible Chart", class: "text-xl font-black text-white")
              p("The SVG has a title and description; the exact values also live in a screen-reader table.", class: "mb-5 mt-2 text-sm text-slate-400")
              chart(
                { "Mon" => 18, "Tue" => 31, "Wed" => 27, "Thu" => 44, "Fri" => 38 },
                type: :line,
                title: "Successful deployments",
                description: "Successful deployments during the current work week.",
                color: :teal,
                id: "advanced-chart",
                class: "rounded-2xl bg-white p-4 text-slate-900"
              )
            end

            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("Safe Canvas", class: "text-xl font-black text-white")
              p("A bounded command vocabulary draws pixels without eval, URLs, arbitrary paths, or executable code.", class: "mb-5 mt-2 text-sm text-slate-400")
              canvas(
                id: "advanced-canvas",
                width: 640,
                height: 360,
                label: "Service health drawing",
                class: "overflow-hidden rounded-2xl bg-white p-4 text-slate-900",
                commands: [
                  { type: :clear, color: :white },
                  { type: :fill_rect, x: 50, y: 80, width: 130, height: 210, color: :blue },
                  { type: :fill_rect, x: 255, y: 130, width: 130, height: 160, color: :purple },
                  { type: :fill_rect, x: 460, y: 45, width: 130, height: 245, color: :green },
                  { type: :line, x1: 35, y1: 290, x2: 605, y2: 290, color: :gray, line_width: 2 },
                  { type: :text, x: 320, y: 330, text: "API      Jobs      Search", align: :center, size: 18, color: :black }
                ]
              )
            end

            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("Schematic Map", class: "text-xl font-black text-white")
              p("Coordinates stay on the server. No tile vendor receives location data, and the view never claims navigation semantics.", class: "mb-5 mt-2 text-sm text-slate-400")
              map(
                center: [51.5074, -0.1278],
                span: [0.18, 0.32],
                label: "London service points",
                id: "advanced-map",
                class: "rounded-2xl bg-white p-4 text-slate-900",
                markers: [
                  map_marker(latitude: 51.5074, longitude: -0.1278, label: "Westminster", detail: "Primary service point"),
                  map_marker(latitude: 51.5155, longitude: -0.0922, label: "City", detail: "Weekday service"),
                  map_marker(latitude: 51.5033, longitude: -0.1195, label: "South Bank", detail: "Event service")
                ]
              )
            end

            article(class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
              h2("Sandboxed WebView", class: "text-xl font-black text-white")
              p("External documents require a dedicated host allowlist. This same-origin example receives an empty sandbox capability set.", class: "mb-5 mt-2 text-sm text-slate-400")
              web_view(
                "/up",
                title: "Application health endpoint",
                id: "advanced-web-view",
                class: "min-h-48 rounded-2xl bg-white"
              )
            end
          end
        end
      end
    end
  end
end
