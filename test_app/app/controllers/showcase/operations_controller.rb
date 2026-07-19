# frozen_string_literal: true

module Showcase
  class OperationsController < ApplicationController
    SESSION_KEY = "showcase_operations_state"
    COMPONENT_ID_KEY = "showcase_operations_component_id"

    def show
      load_dashboard
    end

    def event
      @state = OperationsState.new(session[SESSION_KEY])
      @state.apply!(params[:event_type], service_id: params[:service_id])
      session[SESSION_KEY] = @state.to_h
      load_capability
      broadcast_update

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "operations-dashboard",
            partial: "showcase/operations/dashboard",
            locals: { state: @state }
          )
        end
        format.html { redirect_to showcase_operations_path, notice: "Operations event applied." }
        format.json { render json: { summary: @state.summary, services: @state.services } }
      end
    rescue ArgumentError
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to showcase_operations_path, alert: "That operations event is not available." }
        format.json { render json: { error: "Invalid operations event" }, status: :unprocessable_entity }
      end
    end

    private

    def load_dashboard
      @state = OperationsState.new(session[SESSION_KEY])
      session[SESSION_KEY] = @state.to_h
      load_capability
    end

    def load_capability
      numeric_suffix = SecureRandom.random_number(900_000_000) + 100_000_000
      session[COMPONENT_ID_KEY] ||= "swift-ui-operations-dashboard-#{numeric_suffix}"
      @component_id = session[COMPONENT_ID_KEY]
      # This public, read-only showcase has no authenticated principal. The
      # short-lived capability is bound to its unguessable dashboard stream;
      # production private streams must also supply an authorization context.
      @stream_token = SwiftUIRails::Reactive::ReactiveStreamToken.generate(@component_id)
    end

    def broadcast_update
      ShowcaseOperationsChannel.broadcast_to(
        @component_id,
        {
          action: "operations_update",
          summary: @state.summary,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end
