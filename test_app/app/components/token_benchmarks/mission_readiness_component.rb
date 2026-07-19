# frozen_string_literal: true

module TokenBenchmarks
  class MissionReadinessComponent < ApplicationComponent
    prop :mission, type: Hash, required: true
    prop :systems, type: Array, required: true

    swift_ui do
      component = @component

      vstack(alignment: :leading, spacing: 18) do
        hstack(spacing: 12) do
          vstack(alignment: :leading, spacing: 2) do
            text(component.mission.fetch("phase")).text_style(:supporting)
            text(component.mission.fetch("name")).text_style(:title).accessibility_heading(level: 1)
          end
          spacer
          button("Run diagnostic").button_style(:bordered)
        end

        grid(columns: 3, spacing: 12) do
          article do
            text("Mission progress").text_style(:headline).accessibility_heading(level: 2)
            progress_view(
              value: component.mission.fetch("progress"),
              total: 100,
              label: "Mission progress"
            )
          end
            .padding(4)
            .background_style(:surface)
            .rounded("xl")
          article do
            text("Readiness").text_style(:headline).accessibility_heading(level: 2)
            gauge(value: component.mission.fetch("readiness"), label: "Readiness")
          end
            .padding(4)
            .background_style(:surface)
            .rounded("xl")
          article do
            text("Systems").text_style(:headline).accessibility_heading(level: 2)
            text(component.systems.length.to_s).text_style(:title)
          end
            .padding(4)
            .background_style(:surface)
            .rounded("xl")
        end

        vstack(alignment: :leading, spacing: 8) do
          component.systems.each do |system|
            hstack(id: "system-#{system.fetch("id")}", spacing: 8) do
              text(system.fetch("name")).text_style(:body)
              spacer
              if system.fetch("operational")
                badge("Operational", tone: :success)
              else
                badge("Attention", tone: :warning)
              end
            end
              .padding(4)
              .background_style(:surface)
              .rounded("lg")
          end
        end
      end
        .padding(6)
        .background_style(:canvas)
        .rounded("2xl")
    end
  end
end
