# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: the schematic map remains static while Rails-owned URL
# state selects and clears station detail.
class DemosDispatchTest < ApplicationSystemTestCase
  test "selecting and clearing stations through the URL" do
    visit_demo("dispatch")

    assert_selector "svg"
    assert_selector "a[data-dispatch-station]", count: Demos::DispatchNetwork.stations.length

    click_link "West Yard"
    assert_current_path(/station=west-yard/, wait: 5)
    assert_selector "[data-dispatch-detail='west-yard']"
    assert_text "generator maintenance"

    click_link "Clear selection"
    assert_no_selector "[data-dispatch-detail]"

    assert_demo_healthy
  end
end
