# frozen_string_literal: true

class AtlasMissionControlStories < ViewComponent::Storybook::Stories
  def command_center
    state = Showcase::MissionControlState.new(mission_session_state)
    presentation = story_params[:presentation].to_s
    presentation = nil unless AtlasMissionControlComponent::PRESENTATIONS.include?(presentation)

    AtlasMissionControlComponent.new(
      phase: state.phase,
      sequence_items: state.sequence_items,
      system_items: state.system_items,
      alert_items: state.alert_items,
      telemetry: state.telemetry,
      activity: state.activity,
      summary: {
        readiness: state.readiness,
        hold_count: state.hold_count,
        escalated_alerts: state.escalated_alerts,
        mission_status: state.mission_status
      },
      document: state.document,
      surface: :storybook,
      presentation: presentation
    )
  end

  private

  # Story action reconstruction may run without a request-backed controller.
  # A fresh state object is the safe, deterministic fallback in that context.
  def mission_session_state
    view_context.controller.session[Showcase::MissionControlController::SESSION_KEY]
  rescue NoMethodError, RuntimeError
    nil
  end

  def story_params
    view_context.params
  rescue NoMethodError, RuntimeError
    {}
  end
end
