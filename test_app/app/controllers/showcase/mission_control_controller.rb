# frozen_string_literal: true

module Showcase
  class MissionControlController < ApplicationController
    SESSION_KEY = :showcase_mission_control_state
    DOCUMENT_MAX_BYTES = MissionControlState::MAX_DOCUMENT_BYTES
    DOCUMENT_CONTENT_TYPES = %w[text/plain application/pdf].freeze
    MISSION_PRESENTATIONS = %w[brief transmission reset].freeze
    STORY_NAME = "atlas_mission_control"
    STORY_VARIANT = "command_center"

    before_action :load_mission_state

    def show; end

    def reorder
      values = params.require(:reorder).permit(:item_key, :direction, :target_key, :placement)
      @mission_state.move!(
        item_key: values[:item_key],
        direction: values[:direction],
        target_key: values[:target_key],
        placement: values[:placement]
      )

      respond_with_mission(
        notice: "Launch sequence updated.",
        anchor: "atlas-flight-plan"
      )
    rescue ActionController::ParameterMissing, ArgumentError => error
      respond_with_mission_error(error.message, anchor: "atlas-flight-plan")
    end

    def system_action
      @mission_state.update_system!(params[:system], params[:mission_action])
      respond_with_mission(
        notice: "System readiness updated.",
        anchor: "atlas-systems"
      )
    rescue ArgumentError => error
      respond_with_mission_error(error.message, anchor: "atlas-systems")
    end

    def alert_action
      @mission_state.update_alert!(params[:alert], params[:mission_action])
      respond_with_mission(
        notice: "Flight alert updated.",
        anchor: "atlas-alerts"
      )
    rescue ArgumentError => error
      respond_with_mission_error(error.message, anchor: "atlas-alerts")
    end

    def advance
      @mission_state.advance!
      respond_with_mission(
        notice: "The launch count advanced.",
        anchor: "atlas-mission-overview"
      )
    rescue MissionControlState::InterlockError => error
      respond_with_mission_error(error.message, anchor: "atlas-mission-overview")
    end

    def reset
      @mission_state.reset!
      respond_with_mission(
        notice: "Mission workspace reset.",
        anchor: "atlas-mission-control"
      )
    end

    def import_document
      document = params.require(:document).permit(:creation_context, :file)
      context = verify_document_context!(document[:creation_context], sources: %i[import])
      upload = document[:file]
      SwiftUIRails::DocumentWorkflow.validate_upload!(
        upload,
        max_bytes: DOCUMENT_MAX_BYTES,
        content_types: DOCUMENT_CONTENT_TYPES
      )
      @mission_state.record_document!(
        filename: upload.original_filename,
        bytes: upload.size,
        source: context.fetch(:source)
      )

      respond_with_mission(
        notice: "Mission document inspected safely.",
        anchor: "atlas-documents"
      )
    rescue SwiftUIRails::DocumentWorkflow::ValidationError,
           ActionController::ParameterMissing,
           ArgumentError => error
      respond_with_mission_error(error.message, anchor: "atlas-documents")
    end

    def create_document
      document = params.require(:document).permit(:creation_context)
      context = verify_document_context!(
        document[:creation_context],
        sources: %i[new template duplicate generated]
      )
      @mission_state.record_document!(
        filename: "Atlas launch brief.txt",
        bytes: 0,
        source: context.fetch(:source)
      )

      respond_with_mission(
        notice: "Mission document context verified.",
        anchor: "atlas-documents"
      )
    rescue SwiftUIRails::DocumentWorkflow::ValidationError,
           ActionController::ParameterMissing,
           ArgumentError => error
      respond_with_mission_error(error.message, anchor: "atlas-documents")
    end

    def export_document
      rows = [%w[position sequence status owner]]
      @mission_state.sequence_items.each_with_index do |item, index|
        rows << [index + 1, item.fetch(:key), item.fetch(:status), item.fetch(:owner)]
      end
      body = rows.map { |row| row.map { |value| csv_field(value) }.join(",") }.join("\n") << "\n"

      send_data(
        body,
        type: "text/csv; charset=utf-8",
        disposition: "attachment",
        filename: "atlas-mission-plan.csv"
      )
    end

    private

    def load_mission_state
      @mission_state = MissionControlState.new(session[SESSION_KEY])
      @mission_surface = storybook_surface? ? :storybook : :showcase
      requested_presentation = params[:presentation].to_s
      @mission_presentation = requested_presentation if MISSION_PRESENTATIONS.include?(requested_presentation)
      persist_mission_state
    end

    def persist_mission_state
      session[SESSION_KEY] = @mission_state.to_h
    end

    def respond_with_mission(notice:, anchor:)
      persist_mission_state
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = notice
          render turbo_stream: turbo_stream.replace("atlas-mission-control", mission_component)
        end
        format.html do
          redirect_to mission_location(anchor: anchor), status: :see_other, notice: notice
        end
      end
    end

    def respond_with_mission_error(message, anchor:)
      safe_message = bounded_error_message(message)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = safe_message
          render(
            turbo_stream: turbo_stream.replace("atlas-mission-control", mission_component),
            status: :unprocessable_entity
          )
        end
        format.html do
          redirect_to mission_location(anchor: anchor), status: :see_other, alert: safe_message
        end
      end
    end

    def mission_component
      AtlasMissionControlComponent.new(
        phase: @mission_state.phase.symbolize_keys,
        sequence_items: @mission_state.sequence_items,
        system_items: @mission_state.system_items,
        alert_items: @mission_state.alert_items,
        telemetry: @mission_state.telemetry,
        activity: @mission_state.activity.map(&:symbolize_keys),
        summary: {
          readiness: @mission_state.readiness,
          hold_count: @mission_state.hold_count,
          escalated_alerts: @mission_state.escalated_alerts,
          mission_status: @mission_state.mission_status
        },
        document: @mission_state.document&.symbolize_keys,
        surface: @mission_surface,
        presentation: @mission_presentation
      )
    end

    def mission_location(anchor:)
      if storybook_surface?
        story_path(
          story: STORY_NAME,
          variant: STORY_VARIANT,
          anchor: anchor
        )
      else
        showcase_mission_control_path(anchor: anchor)
      end
    end

    def storybook_surface?
      params[:surface].to_s == "storybook"
    end

    def bounded_error_message(message)
      value = message.to_s
      return "The mission request could not be completed." unless value.valid_encoding?

      value.first(180).presence || "The mission request could not be completed."
    end

    def verify_document_context!(token, sources:)
      context = SwiftUIRails::DocumentWorkflow.verify_creation_context!(token)
      valid_source = sources.include?(context.fetch(:source))
      valid_mission = context.fetch(:metadata).fetch("mission", nil) == "atlas-7"
      return context if valid_source && valid_mission

      raise SwiftUIRails::DocumentWorkflow::ValidationError,
        "document creation context does not match the Atlas mission workflow"
    end

    def csv_field(value)
      text = value.to_s
      text.match?(/[",\r\n]/) ? %("#{text.gsub('"', '""')}") : text
    end
  end
end
