# frozen_string_literal: true

module Demos
  # Flightplan validates every route-backed move and re-renders the
  # authoritative board through a Turbo Stream.
  class FlightplanController < BaseController
    SESSION_KEY = :demos_flightplan_state

    before_action :load_state

    def show; end

    def move
      @state.move!(
        card: params[:card],
        to: params[:to],
        position: params[:position]
      )
      respond_with_demo(board_component, frame_id: "flightplan-board", notice: "Flight plan updated.")
    rescue ArgumentError => error
      respond_with_demo_error(board_component, error.message, frame_id: "flightplan-board")
    end

    def reset
      @state.reset!
      respond_with_demo(board_component, frame_id: "flightplan-board", notice: "Board reset.")
    end

    private

    def load_state
      @state = Demos::FlightplanState.new(session[SESSION_KEY])
      persist_demo_state
    end

    def persist_demo_state
      session[SESSION_KEY] = @state.to_h
    end

    def board_component
      Demos::FlightplanComponent.new(columns: @state.columns)
    end
    helper_method :board_component
  end
end
