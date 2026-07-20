# frozen_string_literal: true

require "test_helper"

module Demos
  class LedgerQueryTest < ActiveSupport::TestCase
    test "returns the first page of the full dataset by default" do
      result = LedgerQuery.call({})

      assert_equal 500, result.total_count
      assert_equal 20, result.total_pages
      assert_equal 1, result.page
      assert_equal 25, result.rows.length
      assert_equal "INV-0001", result.rows.first.id
    end

    test "search matches customer names and invoice ids case-insensitively" do
      by_customer = LedgerQuery.call(q: "acme")
      assert by_customer.total_count.positive?
      assert by_customer.rows.all? { |row| row.customer == "Acme Corp" }

      by_id = LedgerQuery.call(q: "INV-0042")
      assert_equal 1, by_id.total_count
      assert_equal "INV-0042", by_id.rows.first.id
    end

    test "status filter restricts rows and rejects unknown statuses" do
      paid = LedgerQuery.call(status: "paid")
      assert paid.rows.all? { |row| row.status == "paid" }
      assert_equal "paid", paid.status

      bogus = LedgerQuery.call(status: "constantize")
      assert_equal "", bogus.status
      assert_equal 500, bogus.total_count
    end

    test "sorting honors the allowlist and direction" do
      amounts = LedgerQuery.call(sort: "amount", dir: "desc").rows.map(&:amount_cents)
      assert_equal amounts.sort.reverse, amounts

      fallback = LedgerQuery.call(sort: "system('ls')", dir: "sideways")
      assert_equal "id", fallback.sort
      assert_equal "asc", fallback.dir
    end

    test "page numbers clamp to the valid range" do
      assert_equal 1, LedgerQuery.call(page: "-5").page
      assert_equal 20, LedgerQuery.call(page: "9999").page
      assert_equal 25, LedgerQuery.call(page: "9999").rows.length
    end

    test "search queries are bounded to 80 characters" do
      result = LedgerQuery.call(q: "a" * 500)
      assert_equal 80, result.q.length
    end

    test "to_params omits defaults so URLs stay clean" do
      assert_equal({}, LedgerQuery.call({}).to_params)

      params = LedgerQuery.call(q: "acme", sort: "amount", dir: "desc").to_params
      assert_equal({ q: "acme", sort: "amount", dir: "desc" }, params)
    end

    test "to_params omits dir=asc for any ascending sort" do
      assert_equal({ sort: "amount" }, LedgerQuery.call(sort: "amount", dir: "asc").to_params)
    end
  end
end
