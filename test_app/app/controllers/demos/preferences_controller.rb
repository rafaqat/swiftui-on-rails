# frozen_string_literal: true

module Demos
  # Preferences renders the reactive PreferencesComponent; all interaction
  # flows through the gem's signed action endpoints (swift_ui/actions), not
  # through this controller.
  class PreferencesController < BaseController
    def show; end
  end
end
