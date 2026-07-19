# frozen_string_literal: true

module Demos
  # Motion showcase. bump/reveal answer with targeted Turbo Streams so the
  # insertion transitions replay; shuffle redirects so Turbo's page morph and
  # the View Transitions API animate the cards; burst appends staggered
  # toasts into the shared #toasts stack.
  class MotionController < BaseController
    SESSION_KEY = :demos_motion_state

    before_action :load_state

    def show; end

    def bump
      @state.bump!
      persist_demo_state

      render turbo_stream: turbo_stream.replace("motion-count", html: count_html)
    end

    def burst
      persist_demo_state
      toasts = ["Burst one away.", "Burst two right behind.", "Burst three sticks the landing."]
      render turbo_stream: toasts.each_with_index.map { |message, index|
        turbo_stream.append(
          "toasts",
          ToastComponent.new(message: message, variant: "success", duration: 3500 + (index * 400),
                             enter_delay: index * 120)
        )
      }
    end

    def shuffle
      @state.shuffle!
      persist_demo_state
      redirect_to demos_motion_path, status: :see_other
    end

    def reveal
      @state.toggle_reveal!
      persist_demo_state

      render turbo_stream: turbo_stream.replace(
        "motion-reveal",
        html: reveal_html
      )
    end

    def reset
      @state.reset!
      persist_demo_state
      redirect_to demos_motion_path, status: :see_other, notice: "Motion state reset."
    end

    private

    def load_state
      @state = Demos::MotionState.new(session[SESSION_KEY])
      persist_demo_state
    end

    def persist_demo_state
      session[SESSION_KEY] = @state.to_h
    end

    # Re-renders just the replaced fragments through the full component so
    # markup stays single-sourced in Demos::MotionComponent.
    def rendered_component
      ApplicationController.render(Demos::MotionComponent.new(state: @state), layout: false)
    end

    def count_html
      extract_fragment("motion-count")
    end

    def reveal_html
      extract_fragment("motion-reveal")
    end

    def extract_fragment(dom_id)
      fragment = Nokogiri::HTML.fragment(rendered_component).at_css("##{dom_id}")
      raise "Missing ##{dom_id} in MotionComponent output" unless fragment

      fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety -- component output is already sanitized DSL HTML
    end
  end
end
