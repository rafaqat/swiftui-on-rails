# frozen_string_literal: true

require "application_system_test_case"

class StorybookDslCoverageTest < ApplicationSystemTestCase
  INDEX_STORIES = %w[
    advanced_content
    atlas_mission_control
    auth_form
    button_preview
    command_palette
    counter_component
    dsl_button
    dsl_card
    dsl_composition
    dsl_product_card
    dsl_studio
    enhanced_auth
    kanban_card
    enhanced_grid
    new_dsl_methods
    navigation_presentation
    preferences
    product_layout_simple
    stat_card
    swift_ui_rails_playground
    swiftui_preview_demo
    toast
    wwdc26_workflows
  ].freeze

  test "every story advertised on the index renders its selected preview" do
    visit rails_stories_path

    advertised_stories = all("article[data-story-key]").to_h do |card|
      [card["data-story-key"], card.find("a", text: "Open preview")[:href]]
    end

    assert_equal INDEX_STORIES.sort, advertised_stories.keys.sort

    advertised_stories.each do |story, launch_url|
      visit launch_url

      assert_selector "#component-preview[data-sui-story='#{story}']"
      assert_selector "form#storybook-controls[method='get']"
      assert_no_selector "[data-controller], [data-action], [data-live-story-target]"
      assert_no_page_errors
    end
  end
end
