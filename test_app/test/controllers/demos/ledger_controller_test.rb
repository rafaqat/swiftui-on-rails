# frozen_string_literal: true

require "test_helper"

module Demos
  class LedgerControllerTest < ActionDispatch::IntegrationTest
    test "renders the ledger with default state" do
      get demos_ledger_path

      assert_response :success
      assert_select "table tbody tr", count: 25
      assert_select "[id='ledger-table']"
    end

    test "URL params drive search, filter, sort, and page state" do
      get demos_ledger_path(q: "acme", status: "paid", sort: "amount", dir: "desc", page: 1)

      assert_response :success
      assert_select "input[name='q'][value='acme']"
      assert_select "select[name='status'] option[selected][value='paid']"
    end

    test "hostile params degrade to defaults instead of erroring" do
      get demos_ledger_path(sort: "../../etc/passwd", dir: "constantize", page: "-1", status: "<script>")

      assert_response :success
      assert_select "table tbody tr", count: 25
    end
  end
end
