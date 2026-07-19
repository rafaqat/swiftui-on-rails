# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: explicit GET form submission and sorting through URL
# navigation. State coverage lives in test/services/demos/ledger_query_test.rb.
class DemosLedgerTest < ApplicationSystemTestCase
  test "search, filter, and sort through the URL" do
    visit_demo("ledger")

    assert_selector "table tbody tr", count: 25

    fill_in "q", with: "acme"
    find("button", text: "Filter").click
    assert_current_path(/q=acme/, wait: 5)
    assert_text "matching “acme”", wait: 5
    assert_selector "table tbody tr td", text: "Acme Corp", wait: 5

    click_link "Amount"
    assert_current_path(/sort=amount/, wait: 5)

    select "Paid", from: "status"
    click_button "Filter"
    assert_current_path(/status=paid/, wait: 5)

    assert_demo_healthy
  end
end
