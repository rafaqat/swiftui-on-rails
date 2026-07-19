# frozen_string_literal: true

module TokenBenchmarks
  class ServiceStatusComponent < ApplicationComponent
    prop :service, type: Hash, required: true

    swift_ui do
      service = @component.service

      hstack(spacing: 8) do
        text(service.fetch("name")).text_style(:headline).accessibility_heading(level: 2)
        spacer
        badge(service.fetch("status"), tone: :success, announce: true)
      end
        .padding(4)
        .background_style(:surface)
        .rounded("xl")
    end
  end
end
