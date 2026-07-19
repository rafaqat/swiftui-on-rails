# frozen_string_literal: true

class AtlasMissionControlComponent < SwiftUIRails::Component::Base
  SURFACES = %i[showcase storybook].freeze
  PRESENTATIONS = %w[brief transmission reset].freeze
  TELEMETRY_WINDOWS = %w[15m 30m 60m].freeze

  COMPOSITION_EXCERPT = <<~RUBY.freeze
    tab_view(label: "Mission workspaces") do
      tab("Telemetry", value: :telemetry) { readiness_chart }
      tab("Sequence",  value: :sequence)  { launch_sequence }
      tab("Documents", value: :documents) { signed_documents }
    end
  RUBY

  GROUND_STATIONS = [
    { latitude: 28.6084, longitude: -80.6043, label: "Launch complex 39A", detail: "Primary launch telemetry" },
    { latitude: 28.3922, longitude: -80.6077, label: "Patrick Space Force Base", detail: "Range safety" },
    { latitude: 27.8498, longitude: -80.4559, label: "Malabar tracking", detail: "Downrange acquisition" }
  ].freeze

  MISSION_BRIEF = <<~HTML.freeze
    <h3>Atlas flight rule 4.2</h3>
    <p>The launch director may advance the count only when every flight system is
    <strong>GO</strong> and no alert remains escalated.</p>
    <blockquote>Rails owns every command. Browser gestures reveal or submit the same
    signed, CSRF-protected operations exposed to keyboard and no-JavaScript users.</blockquote>
    <ul>
      <li>Reorder the launch sequence by stable key.</li>
      <li>Place systems on hold without creating client-owned state.</li>
      <li>Import and export flight documents with verified provenance.</li>
    </ul>
  HTML

  prop :phase, type: Hash, required: true
  prop :sequence_items, type: Array, required: true
  prop :system_items, type: Array, required: true
  prop :alert_items, type: Array, required: true
  prop :telemetry, type: Hash, required: true
  prop :activity, type: Array, required: true
  prop :summary, type: Hash, required: true
  prop :document, type: [Hash, NilClass], default: nil
  prop :surface, type: Symbol, default: :showcase, enum: SURFACES
  prop :presentation, type: [String, NilClass], default: nil

  state :precision_tracking, false, type: [TrueClass, FalseClass]
  state :orbit_zoom, 1, type: Integer
  binding :telemetry_window, type: String, default: "60m"
  binding :command_query, type: String, default: ""
  focus_state :focused_control, values: %i[command]
  environment :color_scheme, default: :dark, type: Symbol
  environment :reduced_motion, default: false, type: [TrueClass, FalseClass]

  swift_ui do
    component = @component

    div(class: "min-h-screen w-full overflow-hidden bg-slate-950", data: { swift_ui_theme: "dark" }) do
      header(class: "relative overflow-hidden border-b border-white/10 bg-slate-950") do
        div(class: "absolute inset-0 bg-gradient-to-br from-cyan-400/10 via-transparent to-violet-500/10", aria: { hidden: true })

        div(class: "relative mx-auto max-w-7xl px-5 py-7 sm:px-8") do
          hstack(alignment: :center, spacing: 16, class: "flex-wrap justify-between") do
            div(class: "min-w-0") do
              hstack(alignment: :center, spacing: 8, class: "flex-wrap") do
                badge("ATLAS-7", tone: :info, class: "font-black tracking-[0.18em]")
                badge(
                  component.value_from(component.summary, :mission_status),
                  tone: component.value_from(component.summary, :mission_status) == "GO" ? :success : :danger,
                  announce: true,
                  id: "atlas-mission-status"
                )
                badge("#{component.color_scheme.to_s.upcase} CONSOLE", tone: :neutral)
              end
              h1("Orbital launch command")
                .font(:large_title)
                .foreground_style(:primary)
                .tw("mt-4 tracking-tight sm:text-5xl")
              p(
                "A route-backed, server-authoritative flight workspace composed entirely with the SwiftUI Rails DSL.",
                class: "mt-3 max-w-3xl sm:text-base"
              ).text_style(:supporting)
            end

            div(class: "grid min-w-64 grid-cols-2 gap-3", aria: { label: "Current mission phase" }) do
              div(class: "rounded-2xl border border-cyan-300/20 bg-cyan-300/5 p-4") do
                text("COUNT")
                  .font(:caption2)
                  .foreground_style(:accent)
                  .tw("block font-black tracking-[0.24em]")
                text(component.value_from(component.phase, :code))
                  .font(:title)
                  .foreground_style(:primary)
                  .tw("mt-2 block font-mono font-black")
              end
              div(class: "rounded-2xl border border-violet-300/20 bg-violet-300/5 p-4") do
                text("PHASE")
                  .font(:caption2)
                  .foreground_style(:accent)
                  .tw("block font-black tracking-[0.24em]")
                text(component.value_from(component.phase, :name))
                  .text_style(:headline)
                  .tw("mt-2 block leading-5")
              end
            end
          end

          navigation_stack(label: "Atlas command navigation", class: "mt-7") do
            toolbar(
              id: "atlas-command-toolbar",
              label: "Mission command toolbar",
              overflow_label: "More mission commands",
              minimize_on_scroll: true,
              minimize_threshold: 40,
              class: "rounded-2xl border border-white/10 bg-white/5 p-2"
            ) do
              toolbar_item(placement: :navigation, priority: :pinned) do
                navigation_link(
                  "Showcase",
                  destination: "/",
                  class: "inline-flex rounded-xl px-3 py-2 text-sm font-bold text-cyan-200 hover:bg-white/10"
                )
              end
              toolbar_item(placement: :primary_action, priority: :pinned) do
                presentation_trigger(
                  "Mission brief",
                  target: "atlas-command-sheet",
                  fallback: "#{component.show_path(presentation: "brief")}#atlas-command-sheet",
                  class: "inline-flex rounded-xl bg-cyan-300 px-3 py-2 text-sm font-black text-slate-950"
                )
              end
              toolbar_item(placement: :secondary_action, priority: :high) do
                presentation_trigger(
                  "Latest transmission",
                  target: "atlas-transmission-alert",
                  fallback: "#{component.show_path(presentation: "transmission")}#atlas-transmission-alert",
                  class: "inline-flex rounded-xl border border-white/15 px-3 py-2 text-sm font-bold text-white"
                )
              end
              toolbar_item(placement: :status, visibility: :visible) do
                button(
                  component.precision_tracking ? "Precision on" : "Precision off",
                  id: "atlas-precision-control",
                  type: "button",
                  class: "rounded-xl border border-violet-300/30 bg-violet-300/10 px-3 py-2 text-sm font-bold text-violet-100"
                )
                  .accessibility_state(pressed: component.precision_tracking)
                  .on_tap { component.precision_tracking = !component.precision_tracking }
                  .on_long_press(minimum_duration: 0.6) { component.precision_tracking = true }
              end
              toolbar_item(placement: :destructive_action, priority: :low, visibility: :overflow) do
                presentation_trigger(
                  "Reset rehearsal",
                  target: "atlas-abort-confirmation",
                  fallback: "#{component.show_path(presentation: "reset")}#atlas-abort-confirmation",
                  class: "inline-flex rounded-xl border border-red-300/30 px-3 py-2 text-sm font-bold text-red-200"
                )
              end
            end
          end
        end
      end

      section(id: "atlas-mission-overview", class: "mx-auto w-full max-w-7xl px-5 py-8 sm:px-8") do
        render_flash

        div(class: "mb-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4", id: "atlas-readiness-summary") do
          component.summary_cards.each do |card|
            metric_card(card)
          end
        end

        environment_scope(atlas_density: :compact) do
          article(id: "atlas-composition", class: "mb-6 grid gap-4 rounded-2xl border border-cyan-300/20 bg-cyan-300/5 p-5 lg:grid-cols-[0.6fr_1.4fr]") do
            div do
              text("COMPOSITION, NOT CONFIGURATION")
                .text_style(:caption)
                .foreground_style(:accent)
                .tw("block font-black tracking-[0.18em]")
              text("One declarative tree composes navigation, state, rich content, workflows, and native fallbacks.")
                .text_style(:supporting)
                .tw("mt-2 block")
            end
            text(AtlasMissionControlComponent::COMPOSITION_EXCERPT)
              .font(:caption)
              .foreground_style(:accent)
              .tw("block whitespace-pre-wrap rounded-xl bg-slate-950 p-4 font-mono")
          end
        end

        tab_view(
          id: "atlas-mission-tabs",
          label: "Mission workspaces",
          selection: :telemetry,
          style: "--swift-ui-tab-color: rgb(203 213 225); --swift-ui-tab-selected-color: rgb(103 232 249); --swift-ui-tab-accent-color: rgb(34 211 238);"
        ) do
          tab("Telemetry", value: :telemetry) do
            div(class: "mt-6 space-y-6") do
              section(class: "grid gap-6 xl:grid-cols-[1.25fr_0.75fr]", aria: { labelledby: "atlas-telemetry-heading" }) do
                panel_shell do
                  hstack(alignment: :center, spacing: 12, class: "mb-5 flex-wrap justify-between") do
                    div do
                      h2("Readiness telemetry", id: "atlas-telemetry-heading")
                        .font(:title2)
                        .foreground_style(:primary)
                      p("Exact values remain available in the chart's screen-reader table.")
                        .text_style(:supporting)
                        .mt(1)
                    end
                    label(for_input: "atlas-telemetry-window", class: "flex items-center gap-2 text-sm font-bold text-slate-300") do
                      text("Window")
                      select(
                        id: "atlas-telemetry-window",
                        class: "rounded-lg border border-white/15 bg-slate-900 px-3 py-2 text-white",
                        **component.telemetry_window.select_attributes
                      ) do
                        option("15m", "15 minutes")
                        option("30m", "30 minutes")
                        option("60m", "60 minutes")
                      end
                    end
                  end
                  chart(
                    component.visible_telemetry,
                    type: :line,
                    title: "Atlas integrated readiness",
                    description: "Readiness percentage during the selected countdown window.",
                    color: component.precision_tracking ? :purple : :teal,
                    id: "atlas-telemetry-chart",
                    class: "rounded-2xl bg-white p-4 text-slate-950"
                  )
                end

                panel_shell do
                  h2("Interlock gauges", class: "text-2xl font-black text-white")
                  p("Native meter and progress elements expose the same values without scripting.", class: "mt-1 text-sm text-slate-400")
                  vstack(alignment: :stretch, spacing: 16, class: "mt-6") do
                    component.interlock_gauges.each do |entry|
                      div(class: "rounded-2xl bg-slate-900 p-4") do
                        hstack(alignment: :center, spacing: 8, class: "justify-between") do
                          text(entry.fetch(:label)).tw("font-bold text-slate-200")
                          text("#{entry.fetch(:value)}%").tw("font-mono text-sm font-black text-cyan-200")
                        end
                        gauge(
                          value: entry.fetch(:value),
                          range: 0..100,
                          label: entry.fetch(:label),
                          class: "mt-3 w-full"
                        )
                      end
                    end
                    progress_view(
                      value: component.value_from(component.summary, :readiness),
                      total: 100,
                      label: "Integrated launch readiness",
                      id: "atlas-readiness-progress",
                      class: "w-full"
                    )
                  end
                end
              end

              section(class: "grid gap-6 xl:grid-cols-2") do
                panel_shell do
                  hstack(alignment: :center, spacing: 8, class: "mb-5 justify-between") do
                    div do
                      h2("Orbital insertion canvas", class: "text-2xl font-black text-white")
                      p("Drag horizontally or use arrow keys to change the bounded trajectory zoom.", class: "mt-1 text-sm text-slate-400")
                    end
                    badge("#{component.orbit_zoom}×", tone: :info, id: "atlas-orbit-zoom")
                  end
                  canvas(
                    id: "atlas-orbit-canvas",
                    width: 720,
                    height: 380,
                    label: "Atlas orbital insertion schematic at #{component.orbit_zoom} times zoom",
                    fallback: "Atlas flight path schematic with Earth, insertion orbit, and spacecraft marker.",
                    class: "overflow-hidden rounded-2xl bg-slate-900 p-3",
                    commands: component.orbit_commands
                  )
                    .focusable
                    .accessibility_hint("Drag left or right, or use the arrow keys, to adjust trajectory zoom")
                    .on_drag(axis: :horizontal, keyboard_step: 24) do |event|
                      translation = event.detail.is_a?(Hash) ? event.detail.dig("translation", "x").to_f : 0
                      delta = translation.negative? ? -1 : 1
                      component.orbit_zoom = (component.orbit_zoom + delta).clamp(1, 3)
                    end
                end

                panel_shell do
                  h2("Ground tracking network", class: "text-2xl font-black text-white")
                  p("A privacy-preserving schematic: coordinates never leave the Rails render.", class: "mt-1 text-sm text-slate-400")
                  map(
                    center: [28.4, -80.55],
                    span: [1.0, 1.0],
                    markers: component.ground_station_markers,
                    label: "Atlas Florida ground tracking network",
                    id: "atlas-ground-map",
                    class: "mt-5 rounded-2xl bg-white p-4 text-slate-950"
                  )
                end
              end

              lifecycle_scope(
                id: "atlas-health-check",
                class: "rounded-2xl border border-emerald-300/20 bg-emerald-300/5 px-4 py-3 text-sm text-emerald-100"
              ) do
                text("Browser lifecycle attached · same-origin readiness check uses the native fallback first.")
              end
                .on_appear
                .task(url: "/up", method: :get, response: :event)
            end
          end

          tab("Launch sequence", value: :sequence) do
            div(class: "mt-6 grid gap-6 xl:grid-cols-[1.15fr_0.85fr]") do
              section(id: "atlas-sequence-region", class: "rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6") do
                h2("Authoritative launch sequence", class: "text-2xl font-black text-white")
                p(
                  "Move buttons work everywhere. Pointer drag submits the same stable-key Rails form.",
                  class: "mb-5 mt-2 text-sm leading-6 text-slate-400"
                )
                reorderable_collection(
                  items: component.sequence_items,
                  key: :key,
                  item_label: :title,
                  move_path: component.sequence_path,
                  label: "Atlas launch sequence",
                  id: "atlas-flight-plan",
                  layout: :list,
                  method: :patch,
                  param: :reorder,
                  class: "space-y-3"
                ) do |item, index|
                  div(class: "rounded-2xl border border-white/10 bg-slate-900 p-4") do
                    hstack(alignment: :start, spacing: 12) do
                      text((index + 1).to_s).tw("inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-cyan-300 font-black text-slate-950")
                      div(class: "min-w-0 flex-1") do
                        hstack(alignment: :center, spacing: 8, class: "flex-wrap justify-between") do
                          text(component.value_from(item, :title)).tw("font-black text-white")
                          status = component.value_from(item, :status)
                          status_chip(status, tone: component.sequence_tone(status), announce: false)
                        end
                        text(component.value_from(item, :owner)).tw("mt-1 block text-xs font-bold uppercase tracking-wider text-cyan-300")
                        text(component.value_from(item, :detail)).tw("mt-2 block text-sm leading-6 text-slate-400")
                      end
                    end
                  end
                end
              end

              div(class: "space-y-6") do
                section(id: "atlas-systems", class: "rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6", aria: { labelledby: "atlas-system-heading" }) do
                  h2("System interlocks", id: "atlas-system-heading", class: "text-2xl font-black text-white")
                  p("Filter locally through a typed Binding; every GO/HOLD command remains a visible PATCH form.", class: "mt-2 text-sm leading-6 text-slate-400")

                  focus_scope(:atlas_commands, class: "mt-5") do
                    label("Command search", for_input: "atlas-command-query", class: "block text-sm font-bold text-slate-200")
                    input(
                      id: "atlas-command-query",
                      type: "search",
                      placeholder: "Filter systems (Control-K)",
                      class: "mt-2 w-full rounded-xl border border-white/15 bg-slate-900 px-4 py-3 text-white",
                      **component.command_query.input_attributes
                    )
                      .focused(:focused_control, equals: :command)
                      .on_key_press(keys: :k, modifiers: :control, scope: :window, prevent_default: true) do
                        component.focused_control = :command
                      end
                  end

                  div(class: "mt-4 space-y-3", id: "atlas-system-list") do
                    component.filtered_system_items.each do |system|
                      go = swipe_action(
                        "Set GO",
                        action: component.system_action_path(component.value_from(system, :id), "go"),
                        method: :patch,
                        tone: :accent,
                        class: "rounded-lg px-3 py-2 text-sm font-black"
                      )
                      hold = swipe_action(
                        "Set HOLD",
                        action: component.system_action_path(component.value_from(system, :id), "hold"),
                        method: :patch,
                        tone: :destructive,
                        class: "rounded-lg px-3 py-2 text-sm font-black"
                      )
                      swipe_actions(
                        label: "#{component.value_from(system, :name)} system",
                        actions: [go, hold],
                        edge: :trailing,
                        class: "rounded-2xl border border-white/10 bg-slate-900 p-4"
                      ) do
                        hstack(alignment: :center, spacing: 12, class: "justify-between") do
                          div do
                            text(component.value_from(system, :name)).tw("block font-black text-white")
                            text("#{component.value_from(system, :detail)} · #{component.value_from(system, :metric)}").tw("mt-1 block text-xs text-slate-400")
                          end
                          status = component.value_from(system, :status)
                          status_chip(
                            status,
                            tone: status == "go" ? :success : :danger
                          )
                        end
                      end
                    end
                    text("No systems match that command filter.").tw("block rounded-xl bg-slate-900 p-4 text-sm text-slate-400") if component.filtered_system_items.empty?
                  end
                end

                section(id: "atlas-alerts", class: "rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6", aria: { labelledby: "atlas-alert-heading" }) do
                  h2("Flight alerts", id: "atlas-alert-heading", class: "text-2xl font-black text-white")
                  p("Swipe reveals the rail; mutation still requires a visible, focusable form button.", class: "mt-2 text-sm leading-6 text-slate-400")
                  div(class: "mt-4 space-y-3", id: "atlas-alert-list") do
                    component.alert_items.each do |flight_alert|
                      acknowledge = swipe_action(
                        "Acknowledge",
                        action: component.alert_action_path(component.value_from(flight_alert, :id), "acknowledge"),
                        method: :patch,
                        tone: :accent,
                        class: "rounded-lg px-3 py-2 text-sm font-black"
                      )
                      escalate = swipe_action(
                        "Escalate",
                        action: component.alert_action_path(component.value_from(flight_alert, :id), "escalate"),
                        method: :patch,
                        tone: :destructive,
                        class: "rounded-lg px-3 py-2 text-sm font-black"
                      )
                      swipe_actions(
                        label: component.value_from(flight_alert, :title),
                        actions: [acknowledge, escalate],
                        edge: :trailing,
                        class: "rounded-2xl border border-white/10 bg-slate-900 p-4"
                      ) do
                        hstack(alignment: :center, spacing: 12, class: "justify-between") do
                          div(class: "min-w-0") do
                            text(component.value_from(flight_alert, :title)).tw("block font-black text-white")
                            text(component.value_from(flight_alert, :detail)).tw("mt-1 block text-xs text-slate-400")
                          end
                          status = component.value_from(flight_alert, :status)
                          status_chip(
                            status,
                            tone: component.alert_tone(status)
                          )
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          tab("Flight documents", value: :documents) do
            div(class: "mt-6 grid gap-6 xl:grid-cols-[1.1fr_0.9fr]") do
              document_workflow(
                label: "Atlas flight documents",
                id: "atlas-documents",
                class: "rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6"
              ) do
                h2("Signed document workflow", class: "text-2xl font-black text-white")
                p(
                  "Import validates the actual bytes, creation carries signed provenance, and export remains a streaming GET.",
                  class: "mb-5 mt-2 text-sm leading-6 text-slate-400"
                )
                if component.document
                  badge(
                    "#{component.value_from(component.document, :filename)} · #{component.value_from(component.document, :source)}",
                    tone: :success,
                    announce: true,
                    id: "atlas-document-status",
                    class: "mb-4"
                  )
                end

                document_import(
                  action: component.document_import_path,
                  accept: [".txt", "text/plain", ".pdf", "application/pdf"],
                  max_bytes: Showcase::MissionControlState::MAX_DOCUMENT_BYTES,
                  source: :import,
                  metadata: { mission: "atlas-7", surface: component.surface.to_s },
                  label: "Flight rule or PDF package (up to 1 MB)",
                  submit_label: "Verify package",
                  id: "atlas-flight-plan-import",
                  class: "space-y-3 rounded-2xl border border-white/10 bg-slate-900 p-5"
                ) do
                  text("The browser limit is a usability hint; the controller repeats size, type, and content inspection.")
                    .tw("block text-sm leading-6 text-slate-400")
                end

                div(class: "mt-4 flex flex-wrap gap-3") do
                  document_creation_action(
                    "Generate console log",
                    action: component.documents_path,
                    source: :generated,
                    metadata: { mission: "atlas-7", template: "console-log", surface: component.surface.to_s }
                  )
                  document_export(
                    "Export readiness CSV",
                    destination: component.document_export_path,
                    filename: "atlas-readiness.csv",
                    content_type: "text/csv",
                    class: "inline-flex rounded-xl border border-cyan-300 px-4 py-2 font-black text-cyan-200"
                  )
                end
              end

              div(class: "space-y-6") do
                article(class: "rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6") do
                  h2("Sanitized mission brief", class: "text-2xl font-black text-white")
                  rich_text(
                    AtlasMissionControlComponent::MISSION_BRIEF,
                    class: "mt-4 rounded-2xl bg-slate-900 p-5 text-sm leading-7 text-slate-200"
                  )
                end

                article(class: "grid gap-4 rounded-3xl border border-white/10 bg-white/5 p-5 sm:grid-cols-[8rem_1fr] sm:p-6") do
                  async_image(
                    "/icon.svg",
                    alt: "SwiftUI Rails mission application mark",
                    loading_label: "Loading mission mark…",
                    error_label: "Mission mark unavailable",
                    id: "atlas-mission-mark",
                    image_class: "h-28 w-28 object-contain",
                    class: "rounded-2xl bg-slate-900 p-3"
                  )
                  div do
                    h2("Embedded readiness endpoint", class: "text-xl font-black text-white")
                    p("The same-origin frame runs with an empty sandbox capability set.", class: "mt-2 text-sm leading-6 text-slate-400")
                    web_view(
                      "/up",
                      title: "Atlas application readiness endpoint",
                      id: "atlas-readiness-web-view",
                      class: "mt-4 min-h-24 w-full rounded-xl bg-white"
                    )
                  end
                end
              end
            end
          end
        end

        section(class: "mt-8 rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6", aria: { labelledby: "atlas-activity-heading" }) do
          hstack(alignment: :center, spacing: 12, class: "flex-wrap justify-between") do
            div do
              h2("Mission activity", id: "atlas-activity-heading", class: "text-2xl font-black text-white")
              p("Bounded session history records each server-accepted transition.", class: "mt-1 text-sm text-slate-400")
            end
            popover("Count controls", id: "atlas-count-controls", class: "rounded-xl border border-cyan-300/30 bg-cyan-300/10 px-4 py-2 font-black text-cyan-100") do
              vstack(alignment: :stretch, spacing: 10, class: "min-w-56 p-3") do
                secure_form(action: component.advance_path, method: :post, class: "inline-block") do
                  button(
                    "Advance count",
                    type: "submit",
                    class: "w-full rounded-xl bg-emerald-500 px-4 py-2 font-black text-slate-950"
                  )
                end
                text("Advance is rejected while any system or alert interlock remains unresolved.")
                  .tw("block text-xs leading-5 text-slate-500")
              end
            end
          end
          div(class: "mt-5 grid gap-3 md:grid-cols-2", id: "atlas-activity-list") do
            component.activity.each do |entry|
              article(class: "rounded-2xl bg-slate-900 p-4") do
                hstack(alignment: :start, spacing: 10) do
                  badge(component.value_from(entry, :tone).upcase, tone: component.activity_tone(component.value_from(entry, :tone)))
                  div do
                    text(component.value_from(entry, :message)).tw("block text-sm font-bold leading-6 text-slate-200")
                    text(component.value_from(entry, :timestamp)).tw("mt-1 block font-mono text-xs text-slate-400")
                  end
                end
              end
            end
          end
        end
      end

      sheet(
        "Atlas mission brief",
        id: "atlas-command-sheet",
        presented: component.presentation == "brief",
        dismiss_path: component.show_path
      ) do
        vstack(alignment: :stretch, spacing: 16) do
          rich_text(AtlasMissionControlComponent::MISSION_BRIEF, class: "leading-7 text-slate-700")
          navigation_link("Open the portable workflow lab", destination: "/rails/stories/wwdc26_workflows?variant=portable_workflows", class: "font-bold text-blue-700")
        end
      end

      alert(
        "Latest flight transmission",
        id: "atlas-transmission-alert",
        message: component.latest_activity_message,
        presented: component.presentation == "transmission",
        dismiss_path: component.show_path
      )

      confirmation_dialog(
        "Reset the Atlas rehearsal?",
        id: "atlas-abort-confirmation",
        message: "Sequence order, interlocks, alerts, documents, and activity will return to the verified baseline.",
        presented: component.presentation == "reset",
        dismiss_path: component.show_path,
        cancel_label: "Keep current rehearsal"
      ) do
        secure_form(action: component.reset_path, method: :post, class: "inline-block") do
          button(
            "Reset rehearsal",
            type: "submit",
            class: "rounded-xl bg-red-600 px-4 py-2 font-black text-white"
          )
        end
      end
    end
  end

  # This showcase is intentionally a singleton per document so its reactive
  # identity is stable across Turbo replacements and signed action round trips.
  def component_id
    "atlas-mission-control"
  end

  def show_path(presentation: nil)
    query = presentation.present? ? { presentation: presentation } : {}
    if surface == :storybook
      helpers.story_path(story: "atlas_mission_control", variant: "command_center", **query)
    else
      helpers.showcase_mission_control_path(**query)
    end
  end

  def sequence_path
    helpers.showcase_mission_control_sequence_path(**surface_query)
  end

  def system_action_path(system, action)
    helpers.showcase_mission_control_system_action_path(
      system: system,
      mission_action: action,
      **surface_query
    )
  end

  def alert_action_path(flight_alert, action)
    helpers.showcase_mission_control_alert_action_path(
      alert: flight_alert,
      mission_action: action,
      **surface_query
    )
  end

  def advance_path
    helpers.showcase_mission_control_advance_path(**surface_query)
  end

  def reset_path
    helpers.showcase_mission_control_reset_path(**surface_query)
  end

  def document_import_path
    helpers.showcase_mission_control_document_import_path(**surface_query)
  end

  def documents_path
    helpers.showcase_mission_control_documents_path(**surface_query)
  end

  def document_export_path
    helpers.showcase_mission_control_document_export_path(**surface_query)
  end

  def visible_telemetry
    count = { "15m" => 3, "30m" => 4, "60m" => telemetry.length }.fetch(telemetry_window.value, telemetry.length)
    telemetry.to_a.last(count).to_h
  end

  def filtered_system_items
    query = command_query.value.to_s.strip.downcase
    return system_items if query.empty?

    system_items.select do |system|
      %i[id name detail status].map { |key| value_from(system, key) }
        .any? { |value| value.to_s.downcase.include?(query) }
    end
  end

  def summary_cards
    [
      { label: "Integrated readiness", value: "#{value_from(summary, :readiness)}%", detail: "Four independently commanded systems" },
      { label: "Systems on hold", value: value_from(summary, :hold_count).to_s, detail: "Must be zero before count advance" },
      { label: "Escalated alerts", value: value_from(summary, :escalated_alerts).to_s, detail: "Require flight-director resolution" },
      { label: "Tracking mode", value: precision_tracking ? "PRECISION" : "NOMINAL", detail: reduced_motion ? "Reduced motion requested" : "Value-driven transitions enabled" }
    ]
  end

  def interlock_gauges
    winds = alert_items.find { |item| value_from(item, :id) == "winds" }
    range = system_items.find { |item| value_from(item, :id) == "range" }
    [
      { label: "Vehicle", value: value_from(summary, :readiness) },
      { label: "Weather", value: winds && value_from(winds, :status) == "escalated" ? 48 : 86 },
      { label: "Range", value: range && value_from(range, :status) == "go" ? 100 : 62 }
    ]
  end

  def orbit_commands
    radius = 86 + ((orbit_zoom - 1) * 24)
    [
      { type: :clear, color: "#07111f" },
      { type: :circle, x: 360, y: 190, radius: 58, color: :blue },
      { type: :circle, x: 360, y: 190, radius: radius, color: "#22d3ee", fill: false, line_width: 3 },
      { type: :line, x1: 360, y1: 190, x2: 360 + radius, y2: 190, color: :purple, line_width: 2 },
      { type: :circle, x: 360 + radius, y: 190, radius: 9, color: :orange },
      { type: :text, x: 360, y: 198, text: "EARTH", align: :center, size: 18, color: :white },
      { type: :text, x: 360, y: 348, text: "ATLAS INSERTION · #{orbit_zoom}×", align: :center, size: 18, color: :white }
    ]
  end

  def ground_station_markers
    GROUND_STATIONS.map { |station| map_marker(**station) }
  end

  def value_from(hash, key)
    hash.fetch(key) { hash.fetch(key.to_s) }
  end

  def latest_activity_message
    return "No flight transmissions recorded." if activity.empty?

    value_from(activity.first, :message)
  end

  def sequence_tone(status)
    { "complete" => :success, "active" => :info, "queued" => :neutral }.fetch(status.to_s, :neutral)
  end

  def alert_tone(status)
    { "open" => :warning, "acknowledged" => :success, "escalated" => :danger }.fetch(status.to_s, :neutral)
  end

  def activity_tone(tone)
    { "info" => :info, "success" => :success, "warning" => :warning, "critical" => :danger }.fetch(tone.to_s, :neutral)
  end

  def validate_props!
    super
    raise ArgumentError, "surface must be showcase or storybook" unless SURFACES.include?(surface)
    if presentation && !PRESENTATIONS.include?(presentation)
      raise ArgumentError, "presentation must be brief, transmission, or reset"
    end

    true
  end

  private

  def metric_card(card)
    article(class: "rounded-2xl border border-white/10 bg-white/5 p-5") do
      text(card.fetch(:label)).text_style(:metadata).tw("block font-black uppercase tracking-[0.18em]")
      text(card.fetch(:value)).text_style(:title).tw("mt-3 block font-mono font-black")
      text(card.fetch(:detail)).text_style(:caption).tw("mt-2 block")
    end
  end

  def panel_shell(class_name: nil, &block)
    classes = ["rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6", class_name].compact.join(" ")
    article(class: classes, &block)
  end

  def status_chip(status, tone:, announce: true)
    badge(status.to_s.upcase, tone: tone, announce: announce)
  end

  def render_flash
    [[helpers.flash[:notice], :success], [helpers.flash[:alert], :danger]].each do |message, tone|
      next if message.blank?

      badge(
        message.to_s.first(240),
        tone: tone,
        announce: true,
        class: "mb-4 block rounded-xl px-4 py-3"
      )
    end
  end

  def surface_query
    surface == :storybook ? { surface: "storybook" } : {}
  end

end
