# frozen_string_literal: true

require "test_helper"

class StatelessDemoControllerTest < ActionDispatch::IntegrationTest
  test "normalizes invalid navigation and filter parameters" do
    get stateless_demo_path,
        params: { tab: "../../admin", filters: { category: "not-a-category" } }

    assert_response :success
    assert_select "h1", text: "Rails-First Stateless Components Demo"
    assert_select "span", text: "Filter Products"
    assert_select "h3", text: "iPhone 15 Pro"
  end

  test "clamps pagination to the available range" do
    get stateless_demo_path, params: { page: -10 }
    assert_response :success
    assert_select "h3", text: "iPhone 15 Pro"

    get stateless_demo_path, params: { page: 10_000 }
    assert_response :success
    assert_select "h3", text: "Columbia Jacket"
  end

  test "bounds search input before rendering and matching" do
    query = "nike" + ("x" * 200)

    get stateless_demo_path, params: { q: query }

    assert_response :success
    assert_select "input[name='q']" do |inputs|
      assert_equal StatelessDemoController::MAX_SEARCH_QUERY_LENGTH,
        inputs.first["value"].length
    end
  end
end
