# frozen_string_literal: true

require "application_system_test_case"

class StorybookInteractiveTest < ApplicationSystemTestCase
  test "catalog exposes only registered server-rendered previews" do
    visit rails_stories_path

    assert_selector "h1", text: "Inspect the system, not screenshots."
    assert_text "Composition Dashboard"
    assert_text "DSL Button"
    assert_text "Product Card"
    assert_text "Atlas Mission Control"
    assert_selector "a", text: "Open preview", count: StoryCatalog.entries.length
    assert_no_text "Simple Button Component"
  end

  test "story page exposes explicit controls, semantic context, and preview" do
    visit story_path(story: "dsl_button")

    assert_selector "form#storybook-controls[method='get']"
    assert_selector "#storybook-control-text[name='text']"
    assert_selector "#component-preview[data-sui-story='dsl_button']",
                    text: "DSL Button - Full Power Showcase"
    assert_selector "#state-inspector", text: "prop_text"
    assert_no_selector "[data-controller], [data-action], [data-live-story-target]"
    assert_no_page_errors
  end

  test "unknown stories return to the index with a useful error" do
    visit story_path(story: "deleted_story")

    assert_current_path rails_stories_path
    assert_selector "[role='alert']", text: "Story not found: deleted_story"
  end

  test "state inspector escapes submitted names and values as text" do
    malicious_key = '<img id="injected-key" src=x onerror=alert(1)>'
    malicious_value = '<script id="injected-value">alert(1)</script>'
    visit story_path(
      story: "dsl_button",
      text: malicious_key,
      aria_label: malicious_value
    )

    stage = find("#component-preview[data-sui-story-session]")
    assert_match(/\A[a-f0-9]{32}\z/, stage["data-sui-story-session"])
    assert_no_selector "#injected-key", visible: :all
    assert_no_selector "#injected-value", visible: :all
    within "#state-inspector" do
      assert_text "injected-key"
      assert_text "onerror=alert(1)"
      assert_text "injected-value"
    end
  end
end
