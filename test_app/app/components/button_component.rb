# frozen_string_literal: true

# @deprecated Use SimpleButtonComponent instead
# This alias will be removed in version 2.0
# ButtonComponent is maintained for backwards compatibility
class ButtonComponent < SimpleButtonComponent
  def initialize(...)
    Rails.deprecator.warn(
      "ButtonComponent is deprecated and will be removed in SwiftUIRails 2.0. " \
      "Please use SimpleButtonComponent instead.",
      caller_locations(1)
    )
    super
  end
end