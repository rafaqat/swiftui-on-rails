# frozen_string_literal: true

require "test_helper"

class StorybookFinalValidationTest < ActionDispatch::IntegrationTest
  test "controls and variant navigation are ordinary Rails inputs and links" do
    get story_path(story: "dsl_card")

    assert_response :success
    assert_select "form#storybook-controls[action=?][method='get']", story_path(story: "dsl_card")
    assert_select "input[name='card_title']"
    assert_select "select[name='background']"
    assert_select "button[type='submit']", text: "Apply controls"
    assert_select "nav[aria-label='Story variants'] a[data-variant='card_gallery']",
                  text: "Card gallery"
    assert_select "#component-preview[data-sui-story-session]"
    assert_select "[data-controller], [data-action], [data-live-story-target]", count: 0
  end

  test "repeated GET previews are deterministic for a story without a component class" do
    %w[white gray-50 blue-50].each_with_index do |background, index|
      get story_path(
        story: "dsl_card",
        story_variant: "default",
        card_title: "Card #{index}",
        background: background
      )

      assert_response :success
      assert_select "#component-preview", text: /Card #{index}/
      assert_not_includes response.body, "Unable to render component preview."
    end
  end

  test "catalog and preview are themselves rendered through SwiftUI Rails IR" do
    get rails_stories_path
    assert_response :success
    assert_select "#storybook-catalog [data-swift-ui-layout-axis]", minimum: 1
    assert_select "a", text: "Open preview →", count: StoryCatalog.entries.length

    get story_path(story: "dsl_card")
    assert_response :success
    assert_select "#storybook-preview-page [data-swift-ui-layout-axis]", minimum: 1
    assert_select "#state-inspector", count: 1
  end
end
