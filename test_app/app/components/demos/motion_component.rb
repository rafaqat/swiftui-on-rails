# frozen_string_literal: true

module Demos
  # The Motion showcase: six animations, each demonstrating a SwiftUI-faithful
  # technique — insertion/removal transitions, ButtonStyle pressed feedback,
  # staggered entrances, Turbo page-morph view transitions, and pure-CSS
  # ambient motion. No client-side animation library anywhere.
  class MotionComponent < ApplicationComponent
    prop :state, type: Object, required: true

    swift_ui do
      component = @component

      grid(columns: 2, spacing: 16) do
        numeric_pop_tile(component.state)
        spring_press_tile
        toast_choreography_tile
        shuffle_tile(component.state)
        staggered_reveal_tile(component.state)
        ambient_tile
      end
    end

    private

    def tile(title, subtitle, &block)
      vstack(spacing: 12, alignment: :start) do
        vstack(spacing: 2, alignment: :start) do
          text(title).tw("text-base font-black text-slate-950")
          text(subtitle).tw("text-xs font-bold text-slate-400")
        end
        instance_exec(&block)
      end.tw("rounded-3xl bg-white p-6 shadow ring-1 ring-slate-900/10")
    end

    # 1 ── Numeric pop: every Turbo Stream replace re-enters with :scale.
    def numeric_pop_tile(state)
      tile("Numeric pop", "Turbo Stream replace + .transition(insertion: :scale)") do
        vstack(spacing: 12, alignment: :center) do
          div(id: "motion-count") do
            text(state.count.to_s)
              .tw("text-7xl font-black tabular-nums tracking-tight text-slate-950")
              .transition(insertion: :scale)
          end

          form(action: helpers.demos_motion_bump_path, method: "post") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            button("Pop it", type: "submit").button_style(:springy).tw("px-6 py-2.5 text-sm font-black")
          end
        end.tw("w-full")
      end
    end

    # 2 ── Spring press: ButtonStyle-flavored pressed feedback, zero JS.
    def spring_press_tile
      tile("Spring press", "button_style(:springy) — bounce-eased :hover/:active, pure CSS") do
        hstack(spacing: 12, alignment: :center) do
          button("Hold me down").button_style(:springy).tw("px-6 py-3 text-sm font-black")
          button("Me too").button_style(:springy).tw("bg-violet-600 px-6 py-3 text-sm font-black")
          button("And me").button_style(:springy).tw("bg-emerald-600 px-6 py-3 text-sm font-black")
        end
      end
    end

    # 3 ── Toast choreography: staggered enter, animated exit.
    def toast_choreography_tile
      tile("Toast choreography", "Staggered :move_up entrances, :opacity exits before removal") do
        form(action: helpers.demos_motion_burst_path, method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button("Launch a burst", type: "submit").button_style(:springy).tw("px-6 py-2.5 text-sm font-black")
        end
        text("Three toasts arrive 120 ms apart, then dismiss themselves.")
          .tw("text-xs font-medium text-slate-500")
      end
    end

    # 4 ── View-transition shuffle: Turbo morph + the View Transitions API
    # FLIP-animates cards to their new grid positions. Zero JavaScript.
    def shuffle_tile(state)
      tile("View-transition shuffle", "Page morph + view-transition-name — the browser animates the moves") do
        grid(columns: 4, spacing: 8) do
          state.order.each { |number| shuffle_card(number) }
        end

        form(action: helpers.demos_motion_shuffle_path, method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button("Shuffle", type: "submit").button_style(:springy).tw("px-6 py-2.5 text-sm font-black")
        end
      end
    end

    def shuffle_card(number)
      div(id: "motion-card-#{number}") do
        text(number.to_s).tw("text-xl font-black text-white")
      end
        .tw("flex h-16 items-center justify-center rounded-2xl bg-gradient-to-br #{Demos::MotionState::CARD_ACCENTS[number - 1]} to-slate-900/60 shadow")
        .style("view-transition-name: motion-card-#{number}")
    end

    # 5 ── Staggered reveal: skeletons swap for content whose rows cascade in.
    def staggered_reveal_tile(state)
      tile("Staggered reveal", "Stream replace; children enter :move_up with cascading delays") do
        div(id: "motion-reveal") do
          if state.revealed?
            vstack(spacing: 8, alignment: :stretch) do
              ["Orbit adjusted", "Telemetry locked", "Crew notified", "Go for launch"].each_with_index do |line, index|
                hstack(spacing: 8, alignment: :center) do
                  icon("check", size: 14).tw("rounded-full bg-emerald-100 p-1 text-emerald-700")
                  text(line).tw("text-sm font-bold text-slate-950")
                end
                  .tw("rounded-2xl bg-slate-50 px-4 py-3")
                  .transition(insertion: :move_up)
                  .style("animation-delay: #{index * 90}ms")
              end
            end
          else
            vstack(spacing: 8, alignment: :stretch) do
              4.times do
                div("").tw("h-11 w-full animate-pulse rounded-2xl bg-slate-100")
              end
            end.tw("w-full")
          end
        end.tw("w-full")

        form(action: helpers.demos_motion_reveal_path, method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(state.revealed? ? "Back to skeletons" : "Reveal", type: "submit")
            .button_style(:springy).tw("px-6 py-2.5 text-sm font-black")
        end
      end
    end

    # 6 ── Ambient hero: keyframes only. No JS, no library, no state.
    def ambient_tile
      tile("Ambient hero", "Pure CSS keyframes — floating light, drifting glow, a passing sheen") do
        div do
          div("").tw("motion-float-a absolute -left-6 top-4 h-32 w-32 rounded-full bg-cyan-400/50 blur-2xl")
          div("").tw("motion-float-b absolute right-2 bottom-0 h-40 w-40 rounded-full bg-violet-500/50 blur-2xl")
          div("").tw("motion-sheen absolute inset-y-0 w-24 -skew-x-12 bg-white/10")
          vstack(spacing: 4, alignment: :start) do
            text("Aurora Deck").tw("text-2xl font-black text-white")
            text("Nothing here is JavaScript.").tw("text-sm font-bold text-white/70")
          end.tw("relative p-6")
        end.tw("relative h-44 w-full overflow-hidden rounded-2xl bg-slate-950")
      end
    end
  end
end
