# frozen_string_literal: true

require "test_helper"

module Demos
  class LedgerComponentTest < ViewComponent::TestCase
    def render_ledger(params = {})
      render_inline(LedgerComponent.new(result: LedgerQuery.call(params)))
    end

    def test_renders_a_native_table_with_rows_and_status_badges
      render_ledger

      assert_selector "table tbody tr", count: 25
      assert_selector "th", text: "Customer"
      assert_selector "span", text: /Paid|Pending|Overdue|Draft/
    end

    def test_sort_headers_link_to_url_state
      render_ledger

      assert_selector "th a[href='/demos/ledger?dir=asc&sort=amount']"
    end

    def test_active_sort_toggles_direction_and_shows_indicator
      render_ledger(sort: "amount", dir: "asc")

      assert_selector "th a[href='/demos/ledger?dir=desc&sort=amount']"
    end

    def test_filters_are_a_plain_get_form
      render_ledger(q: "acme")

      assert_selector "form[action='/demos/ledger'][method='get']"
      assert_selector "input[type='search'][name='q'][value='acme']"
      assert_selector "select[name='status']"
    end

    def test_pagination_preserves_query_state
      render_ledger(status: "paid", page: 2)

      assert_selector "a[href='/demos/ledger?page=1&status=paid']", text: "← Previous"
      assert_selector "a[href='/demos/ledger?page=3&status=paid']", text: "Next →"
    end
  end
end
