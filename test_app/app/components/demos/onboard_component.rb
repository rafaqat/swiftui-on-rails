# frozen_string_literal: true

module Demos
  # A fully server-driven wizard: the current step lives in the URL, every
  # advance is a POST with server-side validation, the browser's back button
  # walks steps naturally, and the success sheet is a native <dialog>. There
  # is no custom JavaScript anywhere in this demo.
  class OnboardComponent < ApplicationComponent
    prop :state, type: Object, required: true
    prop :step, type: Integer, required: true
    prop :error, type: String, default: nil

    swift_ui do
      component = @component
      state = component.state

      vstack(spacing: 16, alignment: :start) do
        # Step indicator
        hstack(spacing: 8, alignment: :center) do
          Demos::OnboardState::STEPS.each_with_index do |step_config, index|
            step_pill(step_config, index + 1)
          end
          spacer
        end
        progress_view(
          value: component.step,
          total: Demos::OnboardState::STEPS.length,
          label: "Onboarding progress"
        ).tw("w-full")

        if component.error
          text(component.error).tw("rounded-2xl bg-rose-100 px-4 py-2 text-sm font-bold text-rose-900")
            .attr("role", "alert")
        end

        form(action: helpers.demos_onboard_advance_path, method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          input(type: "hidden", name: "step", value: component.step)

          vstack(spacing: 16, alignment: :start) do
            case Demos::OnboardState::STEPS[component.step - 1][:key]
            when "profile" then profile_step(state)
            when "workspace" then workspace_step(state)
            when "notifications" then notifications_step(state)
            when "review" then review_step(state)
            end
          end

          toolbar_footer(component.step)
        end
      end
        .tw("mx-auto max-w-2xl rounded-3xl bg-white p-8 shadow ring-1 ring-slate-900/10")

      success_sheet if state.completed?
    end

    private

    def step_pill(step_config, number)
      reachable = number <= state.furthest_step
      current = number == step

      pill = if reachable && !current
        a("#{number}. #{step_config[:title]}", href: helpers.demos_onboard_path(step: number))
      else
        span("#{number}. #{step_config[:title]}")
      end
      pill.tw(
        "rounded-full px-3 py-1.5 text-xs font-black uppercase tracking-widest " +
        if current
          "bg-slate-950 text-white"
        elsif reachable
          "bg-slate-100 text-slate-600 hover:bg-slate-200"
        else
          "bg-slate-50 text-slate-300"
        end
      )
    end

    def field_label(text_content, for_id)
      label(text_content, for_input: for_id)
        .tw("text-xs font-black uppercase tracking-widest text-slate-400")
    end

    def text_field(id, name, value, placeholder)
      input(id: id, name: name, value: value, placeholder: placeholder, required: true)
        .tw("w-full rounded-2xl border border-slate-300 px-4 py-3 text-sm font-medium focus:border-slate-950 focus:outline-none")
    end

    def choice_row(name, options, selected)
      hstack(spacing: 8, alignment: :center) do
        options.each do |option_value|
          label do
            input(
              type: "radio",
              name: name,
              value: option_value,
              checked: selected == option_value,
              required: true
            ).tw("peer sr-only")
            span(option_value)
              .tw("block cursor-pointer rounded-full bg-slate-100 px-4 py-2 text-sm font-black text-slate-600 transition peer-checked:bg-slate-950 peer-checked:text-white")
          end
        end
      end
    end

    def profile_step(state)
      field_label("Full name", "onboard-full-name")
      text_field("onboard-full-name", "full_name", state.values["full_name"], "Ada Lovelace")
      field_label("Role", "onboard-role")
      choice_row("role", Demos::OnboardState::ROLES, state.values["role"])
    end

    def workspace_step(state)
      field_label("Team name", "onboard-team-name")
      text_field("onboard-team-name", "team_name", state.values["team_name"], "Orbital Systems")
      field_label("Team size", "onboard-team-size")
      choice_row("team_size", Demos::OnboardState::TEAM_SIZES, state.values["team_size"])
    end

    def notifications_step(state)
      field_label("Digest cadence", "onboard-digest")
      choice_row("digest", Demos::OnboardState::DIGESTS, state.values["digest"])
      text("You can change this any time — it only affects the summary email.")
        .tw("text-sm font-medium text-slate-500")
    end

    def review_step(state)
      vstack(spacing: 8, alignment: :start) do
        review_row("Name", state.values["full_name"])
        review_row("Role", state.values["role"])
        review_row("Team", "#{state.values['team_name']} (#{state.values['team_size']})")
        review_row("Digest", state.values["digest"])
      end.tw("w-full rounded-2xl bg-slate-50 p-4")
    end

    def review_row(label_text, value)
      hstack(spacing: 8, alignment: :center) do
        text(label_text).tw("w-24 text-xs font-black uppercase tracking-widest text-slate-400")
        text(value).tw("text-sm font-bold text-slate-950")
      end
    end

    def toolbar_footer(current_step)
      last_step = current_step == Demos::OnboardState::STEPS.length
      hstack(spacing: 8, alignment: :center) do
        if current_step > 1
          a("← Back", href: helpers.demos_onboard_path(step: current_step - 1))
            .tw("rounded-full bg-slate-100 px-5 py-2.5 text-sm font-black text-slate-600 transition hover:bg-slate-200")
        end
        spacer
        button(last_step ? "Confirm & finish" : "Continue", type: "submit")
          .tw("rounded-full bg-slate-950 px-6 py-2.5 text-sm font-black text-white transition hover:bg-slate-800")
      end.tw("mt-6 border-t border-slate-100 pt-5")
    end

    def success_sheet
      dialog(open: true, aria: { label: "Onboarding complete" }) do
        vstack(spacing: 12, alignment: :center) do
          icon("check", size: 32).tw("rounded-full bg-emerald-100 p-3 text-emerald-700")
          text("Welcome aboard, #{state.values['full_name']}!").tw("text-xl font-black text-slate-950")
          text("Your workspace “#{state.values['team_name']}” is ready.")
            .tw("text-sm font-bold text-slate-500")
          form(action: helpers.demos_onboard_reset_path, method: "post") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            button("Start over", type: "submit")
              .tw("rounded-full bg-slate-950 px-6 py-2.5 text-sm font-black text-white transition hover:bg-slate-800")
          end
        end
      end.tw("mx-auto mt-[16vh] rounded-3xl bg-white p-8 shadow-2xl backdrop:bg-slate-950/50")
    end
  end
end
