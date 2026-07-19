# frozen_string_literal: true

require "application_system_test_case"

class NavigationPresentationTest < ApplicationSystemTestCase
  test "tabs dialogs popovers and toolbar keys work through progressive enhancement" do
    visit story_path(story: "navigation_presentation", variant: "complete_workflow")

    within "#component-preview" do
      assert_selector "nav[aria-label='Workspace navigation'] a[aria-current='page']", text: "Dashboard"
      assert_selector "[role='tablist'][aria-label='Project sections']"
      assert_text "Overview panel"
      assert_selector "#project-tabs-panel-activity[hidden]", visible: :all

      click_link "Activity"
      assert_text "Activity panel"
      assert_selector "#project-tabs-tab-activity[aria-selected='true']"
      assert_selector "#project-tabs-panel-overview[hidden]", visible: :all

      click_link "Open project sheet"
      assert_selector "dialog#project-sheet[open][role='dialog']"
      assert_field "Project name", with: "Apollo"
      click_button "Close"
      assert_no_selector "dialog#project-sheet[open]"
      assert_equal "Open project sheet", page.evaluate_script("document.activeElement.textContent.trim()")

      click_link "Show save alert"
      assert_selector "dialog#save-alert[open][role='alertdialog']"
      assert_text "Apollo is now visible to the whole team."
      click_button "OK"
      assert_no_selector "dialog#save-alert[open]"

      click_link "Confirm deletion"
      assert_selector "dialog#delete-confirmation[open][role='alertdialog']"
      assert_button "Delete project"
      click_button "Cancel"
      assert_no_selector "dialog#delete-confirmation[open]"

      find("summary", text: "Quick actions").click
      assert_selector "details#quick-actions[open]"
      assert_link "View activity"
      find("summary", text: "Quick actions").send_keys(:escape)
      assert_no_selector "details#quick-actions[open]"

      bold = find("#format-toolbar button", text: "Bold")
      bold.click
      bold.send_keys(:arrow_right)
      assert_equal "Italic", page.evaluate_script("document.activeElement.textContent.trim()")
    end

    assert_no_page_errors
    assert_no_console_errors
  end

  test "toolbar overflows by priority and minimizes without hiding pinned actions" do
    visit story_path(story: "navigation_presentation", variant: "adaptive_toolbar")

    within "#component-preview" do
      assert_selector "#adaptive-toolbar[data-sui-enhanced='toolbar']"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Save"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Status"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Preview"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-overflow-items button", text: "Export", visible: :all
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-overflow-items button", text: "Advanced", visible: :all

      overflow_trigger = find("#adaptive-toolbar summary", text: "More document actions")
      overflow_trigger.click
      assert_selector "#adaptive-toolbar details[open] .swift-ui-toolbar-overflow-items button", text: "Advanced"
      overflow_trigger.send_keys(:arrow_right)
      assert page.evaluate_script(<<~JS)
        document.activeElement.closest("#adaptive-toolbar .swift-ui-toolbar-overflow-items") !== null
      JS
      overflow_trigger.click

      save_control = find("#adaptive-toolbar .swift-ui-toolbar-items button", text: "Save")
      page.execute_script("arguments[0].focus()", save_control)
      assert_equal "Save", page.evaluate_script("document.activeElement.textContent.trim()")

      scroll_region = find("#toolbar-scroll-region")
      page.execute_script(<<~JS, scroll_region)
        arguments[0].scrollTop = 240
        arguments[0].dispatchEvent(new Event("scroll"))
      JS
      assert_selector "#adaptive-toolbar[data-sui-toolbar-minimized='true']"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Save"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Status"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-overflow-items button", text: "Preview", visible: :all
      assert_equal "Save", page.evaluate_script("document.activeElement.textContent.trim()")

      page.execute_script(<<~JS, scroll_region)
        arguments[0].scrollTop = 0
        arguments[0].dispatchEvent(new Event("scroll"))
      JS
      assert_selector "#adaptive-toolbar[data-sui-toolbar-minimized='false']"
      assert_selector "#adaptive-toolbar .swift-ui-toolbar-items button", text: "Preview"
    end

    assert_no_page_errors
    assert_no_console_errors
  end

  test "a tab deep link initializes selection and browser back restores tab history" do
    visit "#{story_path(story: "navigation_presentation", variant: "complete_workflow")}#project-tabs-panel-activity"

    within "#component-preview" do
      assert_selector "#project-tabs-tab-activity[aria-selected='true']"
      assert_text "Activity panel"
      assert_selector "#project-tabs-panel-overview[hidden]", visible: :all

      click_link "Overview"
      assert_selector "#project-tabs-tab-overview[aria-selected='true']"
      assert_equal "#project-tabs-panel-overview", page.evaluate_script("window.location.hash")
    end

    page.go_back

    within "#component-preview" do
      assert_selector "#project-tabs-tab-activity[aria-selected='true']"
      assert_text "Activity panel"
      assert_equal "#project-tabs-panel-activity", page.evaluate_script("window.location.hash")
    end

    page.go_forward

    within "#component-preview" do
      assert_selector "#project-tabs-tab-overview[aria-selected='true']"
      assert_text "Overview panel"
      assert_equal "#project-tabs-panel-overview", page.evaluate_script("window.location.hash")
    end

    assert_no_page_errors
    assert_no_console_errors
  end

  test "an invalid local tab target is not intercepted from its anchor fallback" do
    visit story_path(story: "navigation_presentation", variant: "complete_workflow")

    within "#component-preview" do
      page.execute_script("document.getElementById('project-tabs-panel-activity').remove()")
      click_link "Activity"

      assert_selector "#project-tabs-tab-overview[aria-selected='true']"
      assert_equal "#project-tabs-panel-activity", page.evaluate_script("window.location.hash")
    end

    assert_no_page_errors
    assert_no_console_errors
  end

  test "back to an empty hash restores the immutable server selection" do
    visit story_path(story: "navigation_presentation", variant: "complete_workflow")

    within "#component-preview" do
      assert_selector "#project-tabs-tab-overview[aria-selected='true']"
      click_link "Activity"
      assert_selector "#project-tabs-tab-activity[aria-selected='true']"
      assert_equal "#project-tabs-panel-activity", page.evaluate_script("window.location.hash")
    end

    page.go_back

    within "#component-preview" do
      assert_selector "#project-tabs-tab-overview[aria-selected='true']"
      assert_text "Overview panel"
      assert_equal "", page.evaluate_script("window.location.hash")
    end

    page.go_forward

    within "#component-preview" do
      assert_selector "#project-tabs-tab-activity[aria-selected='true']"
      assert_text "Activity panel"
      assert_equal "#project-tabs-panel-activity", page.evaluate_script("window.location.hash")
    end

    assert_no_page_errors
    assert_no_console_errors
  end
end
