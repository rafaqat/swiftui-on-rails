# frozen_string_literal: true

require "test_helper"

class StorybookRenderingTest < ActionDispatch::IntegrationTest
  test "every discovered story renders its default or first public variant" do
    StorybookStoryRegistry.all.each do |entry|
      get storybook_show_path, params: { story: entry.name }

      assert_response :success, "Story #{entry.name} should be reachable"
      assert_select "#component-preview[data-sui-story=?]", entry.name, count: 1
      assert_not response.body.include?("Error rendering component:"),
                 "Story #{entry.name} should render without a preview error"
    end
  end

  test "interactive button showcase is a registered renderable variant" do
    entry = StorybookStoryRegistry.fetch("dsl_button")

    assert_includes entry.variants, :interactive_showcase

    get storybook_show_path,
        params: { story: entry.name, story_variant: "interactive_showcase" }

    assert_response :success
    assert_select "#component-preview", text: /Interactive DSL Button Showcase/
    assert_select "#component-preview button", text: "Scale Up"
    assert_select "#component-preview [data-controller], #component-preview [data-action]", count: 0
    assert_not_includes response.body, "Error rendering component:"
  end

  test "curated parity labs render their documented default variants" do
    expectations = {
      "atlas_mission_control" => {
        variant: :command_center,
        selectors: %w[
          #atlas-mission-control
          #atlas-command-toolbar
          #atlas-mission-tabs
          #atlas-mission-overview
          #atlas-telemetry-chart
          #atlas-orbit-canvas
          #atlas-ground-map
          #atlas-flight-plan
          #atlas-systems
          #atlas-alerts
          #atlas-documents
          #atlas-flight-plan-import
          #atlas-command-sheet
          #atlas-transmission-alert
          #atlas-abort-confirmation
        ]
      },
      "navigation_presentation" => {
        variant: :complete_workflow,
        selectors: [
          "nav.swift-ui-navigation-stack",
          "#project-tabs.swift-ui-tab-view",
          "#project-sheet.swift-ui-sheet",
          "[role='toolbar'][aria-label='Formatting tools']"
        ]
      },
      "advanced_content" => {
        variant: :content_families,
        selectors: %w[
          #advanced-async-image
          #advanced-chart
          #advanced-canvas
          #advanced-map
          #advanced-web-view
        ]
      },
      "wwdc26_workflows" => {
        variant: :portable_workflows,
        selectors: %w[
          #delivery-order
          #workflow-swipe
          #workflow-documents
          #workflow-document-import
        ]
      }
    }

    expectations.each do |story, expectation|
      get storybook_show_path,
          params: { story: story, story_variant: expectation.fetch(:variant) }

      assert_response :success, "#{story} should render"
      assert_select "#storybook-preview-page", count: 1
      assert_select "h2", text: "DSL Story Source", count: 1
      assert_select "form#storybook-controls[method='get']", count: 1
      assert_select "#state-inspector", count: 1
      assert_select "[tabindex='0'][aria-label='Scrollable story source']", count: 1
      expectation.fetch(:selectors).each do |selector|
        assert_select "#component-preview #{selector}", count: 1,
          message: "Expected #{selector} in the #{story} preview"
      end
      assert_not_includes response.body, "Error rendering component:"
      assert_not_includes response.body, "Unable to render component preview."
    end
  end
end
