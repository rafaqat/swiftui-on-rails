# frozen_string_literal: true

# The showcase's shared body chrome is itself a SwiftUI Rails view. The ERB
# layout is intentionally limited to the browser document/head bootstrap.
class ShowcaseApplicationShellComponent < SwiftUIRails::Component::Base
  UNSAFE_PATH_CHARACTERS = /[\x00-\x20\x7f]/

  prop :page_content, type: Object, required: true
  prop :current_path, type: String, required: true

  swift_ui do
    component = @component

    vstack(spacing: 0)
      .appearance(:showcase_application_shell)
      .background_style(:canvas) do
        navigation_stack(label: "Primary navigation")
          .appearance(:showcase_navigation)
          .background_style(:elevated)
          .foreground_style(:primary) do
            hstack(spacing: 12)
              .appearance(:showcase_navigation_content) do
                navigation_link(
                  destination: component.home_path,
                  current: component.current_path == component.home_path
                ) do
                    text("SR")
                      .appearance(:showcase_brand_mark)
                      .background_style(:accent)
                      .foreground_style(:on_accent)
                      .font(:caption)
                    text("SwiftUI Rails")
                      .appearance(:showcase_brand_name)
                      .font(:headline)
                      .foreground_style(:primary)
                  end.appearance(:showcase_brand_link)

                spacer

                hstack(spacing: 4)
                  .appearance(:showcase_navigation_links) do
                    component.navigation_items.each do |item|
                      navigation_link(
                        item.fetch(:title),
                        destination: item.fetch(:destination),
                        current: component.current_path == item.fetch(:destination)
                      )
                        .appearance(item.fetch(:appearance, :showcase_navigation_link))
                        .font(:subheadline)
                    end
                  end
              end
          end

        main(component.page_content)
          .appearance(:showcase_page_content)
      end
  end

  def home_path
    helpers.root_path
  end

  def navigation_items
    [
      { title: "Playground", destination: helpers.showcase_playground_path },
      { title: "Mission", destination: helpers.showcase_mission_control_path },
      { title: "Calculator", destination: helpers.showcase_calculator_path },
      { title: "Commerce", destination: helpers.showcase_commerce_path },
      { title: "Workspace", destination: helpers.rails_first_demo_path },
      { title: "Operations", destination: helpers.showcase_operations_path },
      { title: "Demos", destination: helpers.demos_path },
      {
        title: "Component Lab",
        destination: helpers.rails_stories_path,
        appearance: :showcase_component_lab_link
      }
    ]
  end

  private

  def validate_props!
    super

    unless current_path.start_with?("/") &&
        !current_path.start_with?("//") &&
        !current_path.match?(UNSAFE_PATH_CHARACTERS)
      raise ArgumentError, "current_path must be an application-relative path"
    end
  end
end
