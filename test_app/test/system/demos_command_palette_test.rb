# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: open the native disclosure and navigate through its
# server-rendered Rails destinations. Mounted on every /demos page through the
# shared chrome.
class DemosCommandPaletteTest < ApplicationSystemTestCase
  test "palette exposes server-rendered commands and navigates on selection" do
    visit demos_path

    find("details#command-palette summary", text: "Jump anywhere").click
    assert_selector "details#command-palette[open]", wait: 5

    within("#command-palette-content") do
      assert_link "Ledger", href: demos_ledger_path
      assert_link "RPN Calculator", href: showcase_calculator_path
      click_link "Ledger"
    end
    assert_current_path demos_ledger_path, wait: 5

    assert_demo_healthy
  end
end
