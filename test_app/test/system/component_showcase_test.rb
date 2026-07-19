# frozen_string_literal: true

require "application_system_test_case"

class ComponentShowcaseTest < ApplicationSystemTestCase
  test "home page shows every flagship application" do
    visit root_path

    assert_selector "h1", text: /Complete interfaces,\s+built the Rails way\./

    expected_workflows = {
      "mission-control" => [showcase_mission_control_path, "Atlas Mission Control"],
      "calculator" => [showcase_calculator_path, "Classic RPN Calculator"],
      "commerce" => [showcase_commerce_path, "Northstar Commerce"],
      "rails-workspace" => [rails_first_demo_path, "Project Workspace"],
      "operations" => [showcase_operations_path, "Operations Control Room"]
    }

    expected_workflows.each do |key, (path, title)|
      within "a[data-showcase-card='#{key}'][href='#{path}']" do
        assert_text title
      end
    end
  end

  test "counter page shows its live demo and documentation" do
    visit counter_path

    assert_selector "h1", text: "Counter Component"
    assert_text "A counter driven by server-owned State and signed Ruby actions"
    assert_selector "a[href='#{root_path}']", text: "Back to Components"

    assert_text "Live Demo"
    assert_text "Usage"
    assert_text "render CounterComponent.new"

    assert_text "Props"
    assert_text "initial_count"
    assert_text "step"
    assert_text "label"

    assert_text "Architecture"
    assert_text "Server-owned State"
    assert_text "Signed Actions"

    assert_text "Try Different Configurations"
    assert_selector "[data-sui-component='CounterComponent']", count: 4
  end

  test "counter page links back to the current showcase" do
    visit counter_path

    click_link "Back to Components"

    assert_current_path root_path
    assert_selector "h1", text: /Complete interfaces,\s+built the Rails way\./
  end

  test "counter demos maintain independent state" do
    visit counter_path

    within "[data-counter='true']", text: /Steps:/ do
      assert_text "Steps: 0"
      click_button "+"
      assert_text "Steps: 5"
      click_button "+"
      assert_text "Steps: 10"
    end

    within "[data-counter='true']", text: /Score:/ do
      assert_text "Score: 100"
      click_button "+"
      assert_text "Score: 110"
      click_button "-"
      assert_text "Score: 100"
    end

    within "[data-counter='true']", text: /Items:/ do
      assert_text "Items: 50"
      click_button "-"
      assert_text "Items: 49"
    end

    within "[data-counter='true']", text: /Counter:/ do
      assert_text "Counter: 0"
    end
  end
end
