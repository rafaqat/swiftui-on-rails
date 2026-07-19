# frozen_string_literal: true

require "test_helper"

module Demos
  class DispatchControllerTest < ActionDispatch::IntegrationTest
    test "renders the schematic map with all stations" do
      get demos_dispatch_path

      assert_response :success
      assert_select "svg"
      assert_select "a[data-dispatch-station]", count: DispatchNetwork.stations.length
      assert_select "[data-controller]", count: 0
    end

    test "station selection is URL-driven" do
      get demos_dispatch_path(station: "west-yard")

      assert_response :success
      assert_select "[data-dispatch-detail='west-yard']"
      assert_select "a", text: "Clear selection"
    end

    test "unknown stations render the unselected view" do
      get demos_dispatch_path(station: "constantize")

      assert_response :success
      assert_select "[data-dispatch-detail]", count: 0
    end
  end
end
