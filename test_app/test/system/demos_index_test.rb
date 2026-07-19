# frozen_string_literal: true

require "application_system_test_case"

# Gallery smoke test: /demos renders every cataloged card, and every
# destination page loads healthily. This replaces per-demo "does it load"
# system tests — per-demo files cover only their headline interaction.
class DemosIndexTest < ApplicationSystemTestCase
  test "gallery renders every demo card and filters by interaction model" do
    visit demos_path

    DemoCatalog.entries.each do |entry|
      assert_selector "[data-demo-card='#{entry.fetch(:slug)}']"
    end

    click_link DemoCatalog.model_label(:cable)
    assert_current_path demos_path(model: "cable")
    expected = DemoCatalog.filtered(:cable)
    assert_selector "[data-demo-card]", count: expected.length

    assert_demo_healthy
  end

  test "every cataloged demo destination loads healthily" do
    DemoCatalog.entries.each do |entry|
      visit_demo(entry.fetch(:slug))
      assert_demo_healthy
    end
  end
end
