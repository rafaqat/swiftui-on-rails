# frozen_string_literal: true

require "test_helper"

class HomePageRenderingTest < ActionDispatch::IntegrationTest
  test "home page advertises every flagship workflow with a valid route" do
    get root_path

    assert_response :success
    assert_select "main", count: 1
    assert_select "h1", text: /Complete interfaces.*built the Rails way/m
    assert_select "h2", text: "Try the whole workflow."

    expected_workflows = {
      "playground" => [showcase_playground_path, "SwiftUI Rails Playground"],
      "mission-control" => [showcase_mission_control_path, "Atlas Mission Control"],
      "calculator" => [showcase_calculator_path, "Classic RPN Calculator"],
      "commerce" => [showcase_commerce_path, "Northstar Commerce"],
      "rails-workspace" => [rails_first_demo_path, "Project Workspace"],
      "operations" => [showcase_operations_path, "Operations Control Room"]
    }

    expected_workflows.each do |key, (path, title)|
      assert_select "a[data-showcase-card=?][href=?]", key, path, count: 1 do
        assert_select "h3", text: title
      end
    end

    assert_select "a[href=?]", rails_stories_path, minimum: 1
    assert_select "nav[aria-label='Primary navigation'] a[href=?]", showcase_mission_control_path, text: "Mission", count: 1
    assert_select "a[href=?]", stateless_demo_path, count: 1
    assert_select "a[href=?]", counter_path, count: 1
    assert_select "a[href=?]", catalog_products_path, count: 1
    assert_select "dl div", text: /Flagship apps\s*6/, count: 1
    assert_select "dl div", text: /Curated labs\s*#{StoryCatalog.entries.length}/, count: 1
    assert_select "a[href=?]", rails_stories_path, text: "Browse #{StoryCatalog.entries.length} curated labs →", count: 1
  end
end
