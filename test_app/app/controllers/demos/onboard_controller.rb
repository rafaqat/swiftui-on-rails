# frozen_string_literal: true

module Demos
  # Onboard is entirely server-driven: ?step=n addresses a step (clamped to
  # the furthest validated step), advancing is a POST that validates, and the
  # back button walks history naturally.
  class OnboardController < BaseController
    SESSION_KEY = :demos_onboard_state

    before_action :load_state

    def show
      @step = @state.clamp_step(params[:step])
      @error = nil
    end

    def advance
      step = @state.clamp_step(params[:step])
      error = @state.apply_step!(step, scalar_step_input(step))
      persist_demo_state

      if error
        @step = step
        @error = error
        render :show, status: :unprocessable_entity
      else
        next_step = [ step + 1, Demos::OnboardState::STEPS.length ].min
        redirect_to demos_onboard_path(step: next_step), status: :see_other
      end
    end

    def reset
      @state.reset!
      persist_demo_state
      redirect_to demos_onboard_path(step: 1), status: :see_other, notice: "Onboarding reset."
    end

    private

    def scalar_step_input(step)
      Demos::OnboardState::STEPS.fetch(step - 1).fetch(:fields).to_h do |field|
        value = params[field]
        [ field, value.is_a?(String) ? value : nil ]
      end
    end

    def load_state
      @state = Demos::OnboardState.new(session[SESSION_KEY])
      persist_demo_state
    end

    def persist_demo_state
      session[SESSION_KEY] = @state.to_h
    end
  end
end
