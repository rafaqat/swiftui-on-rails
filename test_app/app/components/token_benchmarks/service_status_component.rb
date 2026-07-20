# frozen_string_literal: true

module TokenBenchmarks
  class ServiceStatusComponent < ApplicationComponent
    prop :service, type: Hash, required: true

    # Map each service status to its badge tone. Unknown statuses fall back to
    # :warning so an unrecognized state never reads as healthy.
    STATUS_TONES = {
      "operational" => :success,
      "degraded" => :warning,
      "outage" => :danger,
      "maintenance" => :warning
    }.freeze

    swift_ui do
      service = @component.service
      status = service.fetch("status")

      hstack(spacing: 8) do
        text(service.fetch("name")).text_style(:headline).accessibility_heading(level: 2)
        spacer
        badge(status, tone: STATUS_TONES.fetch(status.to_s.downcase, :warning), announce: true)
      end
        .padding(4)
        .background_style(:surface)
        .rounded("xl")
    end
  end
end
