# frozen_string_literal: true

require "application_system_test_case"

class RailsFirstDemoTest < ApplicationSystemTestCase
  test "manages a task through the Turbo-powered workspace" do
    visit rails_first_demo_path

    assert_selector "h1", text: "Rails-first workspace"
    assert_selector "#rails-todos li", count: 3
    assert_selector "#workspace-metrics [role='progressbar'][aria-valuenow='33']", visible: :all

    fill_in "New task", with: "Prepare the release candidate"
    click_button "Add task"

    assert_selector "#rails-todos li", text: "Prepare the release candidate"
    assert_selector "#workspace-metrics", text: "4"
    assert_selector "#recent-activity", text: "Task added"

    task = find("#rails-todos li", text: "Prepare the release candidate")
    task.find("button[aria-label='Complete Prepare the release candidate']").click

    task = find("#rails-todos li", text: "Prepare the release candidate")
    task.assert_selector ".line-through", text: "Prepare the release candidate"
    assert_selector "#recent-activity", text: "Task completed"

    task.find("summary", text: "Edit task").click
    within task do
      fill_in "Rename task", with: "Publish the release candidate"
      click_button "Save changes"
    end

    assert_selector "#rails-todos li", text: "Publish the release candidate"
    assert_no_selector "#rails-todos li", text: "Prepare the release candidate"

    task = find("#rails-todos li", text: "Publish the release candidate")
    within task do
      accept_confirm("Remove this task?") { click_button "Delete" }
    end

    assert_no_selector "#rails-todos li", text: "Publish the release candidate"
    assert_selector "#recent-activity", text: "Task removed"
    assert_no_page_errors
    assert_no_console_errors
  end

  test "updates the counter and filters the resource library" do
    visit rails_first_demo_path

    within "#rails-counter" do
      assert_text "0"
      click_button "Send request"
      assert_text "1"
    end
    assert_selector "#recent-activity", text: "Counter advanced"

    within "#product-search-form" do
      fill_in "Search resources", with: "rails"
      select "Books", from: "Resource category"
      click_button "Explore"
    end

    within "#rails-products" do
      assert_text "Rails Architecture Handbook"
      assert_no_text "Hotwire Workshop"
      assert_selector "option[value='books'][selected]"
    end

    assert_current_path rails_first_demo_path
    assert_no_page_errors
    assert_no_console_errors
  end
end
