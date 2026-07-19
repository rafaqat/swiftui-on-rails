# frozen_string_literal: true

module SwiftUi
  class ActionsController < ApplicationController
    include SwiftUIRails::Reactive::ComponentActionsController

    private

    # The demo Storybook keeps its own validated, short-lived state session.
    # Normal application components never enter this branch and must present
    # both reactive capabilities enforced by the shared concern.
    def resolve_swift_ui_storybook_component(action_data)
      return unless action_data[:story_session_id].present? && action_data[:story_name].present?

      unless owned_swift_ui_story_session?(action_data[:story_session_id])
        raise SwiftUIRails::Reactive::ComponentActionsController::InvalidCapabilityError,
          "Story session is not owned by this browser session"
      end

      @swift_ui_story_session = StorySession.find_or_create(
        action_data[:story_name],
        action_data[:story_variant] || "default",
        action_data[:story_session_id]
      )
      component = @swift_ui_story_session.component_instance
      raise SwiftUIRails::SecurityError, "Story component is unavailable" unless component

      component
    end

    def owned_swift_ui_story_session?(candidate)
      owned = session[:storybook_session_id]
      return false unless StorySession.valid_session_id?(candidate) && owned.is_a?(String)
      return false unless candidate.bytesize == owned.bytesize

      ActiveSupport::SecurityUtils.secure_compare(candidate, owned)
    end

    def persist_swift_ui_storybook_component(component, _action_data)
      @swift_ui_story_session&.save_component_state(component)
    end
  end
end
