# frozen_string_literal: true

SwiftUIRails.configure do |config|
  # Default animation duration in milliseconds
  config.default_transition_duration = 300

  # Default animation easing function
  config.default_animation_easing = "ease-out"

  # Component class prefix (e.g., "Swift" would make "SwiftButtonComponent")
  config.component_prefix = ""

  # Enable Tailwind CSS integration
  config.tailwind_enabled = true

  # Reactive endpoints are deny-by-default. Add only component classes whose
  # server actions and bindings have been reviewed.
  config.allowed_components << "ExampleComponent"

  # Optional: include tenant/account identity in every encrypted reactive
  # capability. The default already binds request-rendered capabilities to the
  # Rails session and current_user when available.
  # config.reactive_authorization_context = ->(_subject) { Current.account&.id }
end
