# frozen_string_literal: true

require "application_system_test_case"

class HomePageTest < ApplicationSystemTestCase
  test "home page renders the flagship showcase without browser errors" do
    visit root_path

    assert_current_path root_path
    assert_title "Showcase · SwiftUI Rails"
    assert_selector "h1", text: /Complete interfaces,\s+built the Rails way\./
    assert_selector "a[data-showcase-card]", count: 6
    assert_text "SwiftUI Rails Playground"
    assert_text "Atlas Mission Control"
    assert_text "Classic RPN Calculator"
    assert_text "Northstar Commerce"
    assert_text "Project Workspace"
    assert_text "Operations Control Room"
    assert_link "Mission", href: showcase_mission_control_path
    assert_link "Open component lab →", href: rails_stories_path

    assert_no_page_errors
    assert_no_console_errors
  end
end
