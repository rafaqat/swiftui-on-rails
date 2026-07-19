# frozen_string_literal: true

module Demos
  # Relay: thread selection is URL state; sending and archiving are Turbo
  # Stream verbs that replace the app shell (every send earns a canned reply,
  # so the conversation always progresses).
  class RelayController < BaseController
    SESSION_KEY = :demos_relay_state

    before_action :load_state

    def show
      @selected = @state.find_thread(params[:thread])
      @state.mark_read!(params[:thread]) if @selected
      persist_demo_state
    end

    def send_message
      @state.send_message!(params[:thread], params[:body])
      @selected = @state.find_thread(params[:thread])
      respond_with_demo(app_component, frame_id: "relay-app", notice: "Message sent.",
                        anchor: nil)
    rescue ArgumentError => error
      @selected = @state.find_thread(params[:thread])
      respond_with_demo_error(app_component, error.message, frame_id: "relay-app")
    end

    def archive
      @state.archive!(params[:thread])
      @selected = nil
      respond_with_demo(app_component, frame_id: "relay-app", notice: "Thread archived.")
    rescue ArgumentError => error
      @selected = @state.find_thread(params[:thread])
      respond_with_demo_error(app_component, error.message, frame_id: "relay-app")
    end

    def reset
      @state.reset!
      @selected = nil
      respond_with_demo(app_component, frame_id: "relay-app", notice: "Inbox restored.")
    end

    private

    def load_state
      @state = Demos::RelayState.new(session[SESSION_KEY])
      persist_demo_state
    end

    def persist_demo_state
      session[SESSION_KEY] = @state.to_h
    end

    def app_component
      Demos::RelayComponent.new(
        threads: @state.inbox_threads,
        selected_thread: @selected,
        messages: @selected ? @state.messages_for(@selected[:id]) : [],
        archived_count: @state.archived_count
      )
    end
    helper_method :app_component

    def demo_location(anchor: nil)
      helpers_path = @selected ? helpers.demos_relay_path(thread: @selected[:id]) : helpers.demos_relay_path
      anchor ? "#{helpers_path}##{anchor}" : helpers_path
    end
  end
end
