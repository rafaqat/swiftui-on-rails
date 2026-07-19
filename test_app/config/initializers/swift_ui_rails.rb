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

  # Strict CSS: authored style values must come from the validated palette.
  # Development and test raise domain-phrased errors on hallucinated values
  # (the generate→validate→repair contract); production keeps silent
  # sanitization for untrusted runtime input.
  config.strict_css = Rails.env.development? || Rails.env.test?

  # Atlas uses local State, Binding, FocusState, and gesture actions. Reactive
  # restoration is deny-by-default, so the security-reviewed showcase must be
  # named explicitly before those enhancements can execute.
  config.allowed_components << "AtlasMissionControlComponent"

  # Preferences uses server-owned State/Binding with signed action round
  # trips; reactive restoration is deny-by-default, so it must be allowed
  # explicitly.
  config.allowed_components << "PreferencesComponent"
end

# Story fixtures intentionally use Tailwind Plus' public image CDN. Keep the
# library's default allowlist strict and opt this demo application in explicitly.
SwiftUIRails::Security::URLValidator.add_approved_domain("tailwindcss.com")
