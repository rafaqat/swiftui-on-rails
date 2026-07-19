# frozen_string_literal: true

require "test_helper"

class DemosControllerTest < ActionDispatch::IntegrationTest
  test "gallery lists every cataloged demo" do
    get demos_path

    assert_response :success
    assert_select "[data-demo-card]", count: DemoCatalog.entries.length
    DemoCatalog.entries.each do |entry|
      assert_select "[data-demo-card=?]", entry.fetch(:slug), count: 1
    end
  end

  test "filtering by interaction model is URL-driven" do
    get demos_path(model: "cable")

    assert_response :success
    expected = DemoCatalog.filtered(:cable)
    assert_select "[data-demo-card]", count: expected.length
    assert_select "a[aria-current='page']", text: DemoCatalog.model_label(:cable)
  end

  test "an unknown model filter falls back to the full gallery" do
    get demos_path(model: "constantize")

    assert_response :success
    assert_select "[data-demo-card]", count: DemoCatalog.entries.length
  end

  test "every demo card links to a live destination" do
    get demos_path

    helpers = Rails.application.routes.url_helpers
    DemoCatalog.entries.each do |entry|
      assert_select "a[data-demo-card='#{entry.fetch(:slug)}'][href=?]",
                    DemoCatalog.path_for(entry, helpers)
    end
  end
end
