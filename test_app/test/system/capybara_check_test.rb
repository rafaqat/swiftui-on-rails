# frozen_string_literal: true

require "application_system_test_case"

class CapybaraCheckTest < ApplicationSystemTestCase
  test "headless browser reaches the application root" do
    visit root_path

    assert_current_path root_path
    assert_title "Showcase · SwiftUI Rails"
    assert_selector "main h1", text: /Complete interfaces,\s+built the Rails way\./
  end
end
