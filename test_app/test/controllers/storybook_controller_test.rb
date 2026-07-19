# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class StorybookControllerTest < ActionDispatch::IntegrationTest
  test "catalog renders every trusted story as a real navigation" do
    get rails_stories_path

    assert_response :success
    assert_select "article[data-story-key]", count: StoryCatalog.entries.length
    StoryCatalog.entries.each do |story|
      assert StorybookStoryRegistry.fetch(story.fetch(:path))
      assert_select "article[data-story-key=?]", story.fetch(:path), count: 1 do
        assert_select "a[href=?]",
                      story_path(
                        story: story.fetch(:path),
                        story_variant: story.fetch(:default_variant)
                      ),
                      count: 1
      end
    end
  end

  test "trusted component source is server rendered as inert text" do
    get story_path(story: "atlas_mission_control", story_variant: "command_center")

    assert_response :success
    assert_select "h2", text: "DSL Story Source", count: 1
    assert_select "[aria-label='Scrollable story source']", text: /class AtlasMissionControlComponent/
    assert_select "[aria-label='Scrollable story source']", text: /swift_ui do/
    assert_select "[aria-label='Scrollable story source']", text: /navigation_stack/
    assert_includes response.body, "atlas_mission_control_component.rb"
  end

  test "component-backed story creates one server session and semantic context" do
    get storybook_show_url, params: { story: "counter_component" }

    assert_response :success
    session_id = request.session.fetch(:storybook_session_id)
    assert_match(/\A[a-f0-9]{32}\z/, session_id)
    assert_select "#component-preview[data-sui-story-session=?]", session_id, count: 1
    assert_select "#component-preview[data-sui-story='counter_component']", count: 1
    assert_select "#component-preview[data-sui-story-variant='default']", count: 1
    assert_select "#state-inspector", text: /prop_initial_count/
    assert_select "script:not([type='importmap']):not([type='module'])", count: 0
    refute_includes response.body, "window.storybookSessionId"
  end

  test "GET controls are the sole Storybook prop transition" do
    get story_path(
      story: "dsl_card",
      story_variant: "default",
      card_title: "Updated Card",
      background: "blue-50",
      elevation: "3",
      border_color: "blue-200"
    )

    assert_response :success
    assert_select "form#storybook-controls[method='get']"
    assert_select "input[name='card_title'][value='Updated Card']"
    assert_select "select[name='background'] option[value='blue-50'][selected]"
    assert_select "#component-preview", text: /Updated Card/
    assert_select "#state-inspector", text: /prop_card_title/
    assert_select "#state-inspector", text: /Updated Card/
  end

  test "component preview and state inspector read the same persisted session" do
    persisted_component = CounterComponent.new(initial_count: 91, step: 3, label: "Persisted")
    fake_session = Object.new
    fake_session.define_singleton_method(:update_props) { |_props| self }
    fake_session.define_singleton_method(:component_instance) { persisted_component }
    fake_session.define_singleton_method(:current_state) { { "count" => 91 } }

    StorySession.stub(:find_or_create, fake_session) do
      get story_path(
        story: "counter_component",
        story_variant: "default",
        initial_count: "2",
        step: "1",
        label: "Submitted"
      )
    end

    assert_response :success
    assert_select "#component-preview", text: /Persisted: 91/
    assert_select "#state-inspector", text: /count/
    assert_select "#state-inspector", text: /91/
  end

  test "preview errors are logged but never exposed" do
    renderer = Object.new
    renderer.define_singleton_method(:render_story) { |*| raise "database password from preview" }
    logged_errors = []

    Rails.logger.stub(:error, ->(message) { logged_errors << message }) do
      StoryRenderer.stub(:new, renderer) do
        get story_path(story: "dsl_button", story_variant: "default")
      end
    end

    assert_response :success
    assert_includes response.body, "Unable to render component preview."
    refute_includes response.body, "database password from preview"
    assert logged_errors.any? { |message| message.include?("database password from preview") }
  end

  test "unregistered stories and variants never become Ruby method names" do
    get storybook_show_url, params: { story: "../stories/dsl_card" }
    assert_redirected_to rails_stories_path
    assert_equal "Story not found: ../stories/dsl_card", flash[:alert]

    get storybook_show_url, params: { story: "dsl_card", story_variant: "public_send" }
    assert_redirected_to rails_stories_path
    assert_equal "Story variant not found: public_send", flash[:alert]
  end

  test "select values outside the catalog fall back without reaching CSS output" do
    dangerous_background = "[background:url(javascript:alert(1))]"

    get story_path(
      story: "dsl_button",
      story_variant: "default",
      background_color: dangerous_background,
      size: "not-a-size"
    )

    assert_response :success
    assert_select "#component-preview button.bg-blue-600", count: 1
    assert_select "#component-preview button.text-base", count: 1
    refute_includes response.body, "javascript:alert"
  end

  test "Storybook emits no application JavaScript metadata" do
    get story_path(story: "dsl_button")

    assert_response :success
    assert_select "[data-controller], [data-action]", count: 0
    assert_select "[data-live-story-target], [data-state-inspector-target]", count: 0
    refute_match(/\w+->\w+#\w+/, response.body)
    assert_select "script:not([type='importmap']):not([type='module'])", count: 0
    refute_includes response.body, "window.storybookSessionId"
  end
end
