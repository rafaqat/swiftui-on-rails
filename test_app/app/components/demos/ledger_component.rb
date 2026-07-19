# frozen_string_literal: true

module Demos
  # URL-driven data table: search, status filter, column sorting, and
  # pagination are all plain GET navigations. Turbo page-refresh morphing may
  # preserve focus and scroll, but the form has no application-side JS model.
  class LedgerComponent < ApplicationComponent
    STATUS_BADGES = {
      "draft" => "bg-slate-100 text-slate-700",
      "pending" => "bg-amber-100 text-amber-800",
      "paid" => "bg-emerald-100 text-emerald-800",
      "overdue" => "bg-rose-100 text-rose-800"
    }.freeze

    COLUMNS = [
      %w[id Invoice],
      %w[customer Customer],
      %w[status Status],
      %w[amount Amount],
      %w[issued_on Issued]
    ].freeze

    prop :result, type: Object, required: true

    swift_ui do
      vstack(spacing: 16, alignment: :start) do
        filter_toolbar

        text(summary_line)
          .tw("text-sm font-bold text-slate-500")

        div do
          table do
            caption("Invoice ledger — sort, filter, and paginate through the URL")
              .tw("sr-only")
            thead do
              tr do
                COLUMNS.each { |key, label| sortable_header(key, label) }
              end
            end.tw("bg-slate-50")
            tbody do
              result.rows.each { |row| ledger_row(row) }
            end
          end.tw("min-w-full divide-y divide-slate-200 text-left text-sm")
        end
          .tw("w-full overflow-x-auto rounded-2xl bg-white shadow ring-1 ring-slate-900/10")
          .morph_id("ledger-table")

        pagination_bar
      end
    end

    private

    def filter_toolbar
      form(action: ledger_path, method: "get") do
        hstack(spacing: 8, alignment: :center) do
          input(
            type: "search",
            name: "q",
            value: result.q,
            placeholder: "Search customer or invoice…",
            aria: { label: "Search invoices" }
          ).tw("w-72 rounded-full border border-slate-300 bg-white px-5 py-2.5 text-sm font-medium focus:border-slate-950 focus:outline-none")

          select(name: "status", selected: result.status, aria: { label: "Filter by status" }) do
            option("", "All statuses", selected: result.status.blank?)
            Demos::LedgerDataset::STATUSES.each do |status|
              option(status, status.capitalize, selected: result.status == status)
            end
          end.tw("rounded-full border border-slate-300 bg-white px-4 py-2.5 text-sm font-bold")

          input(type: "hidden", name: "sort", value: result.sort)
          input(type: "hidden", name: "dir", value: result.dir)

          button("Filter", type: "submit")
            .tw("rounded-full bg-slate-950 px-5 py-2.5 text-sm font-black text-white transition hover:bg-slate-800")
        end
      end
    end

    def sortable_header(key, label)
      active = result.sort == key
      next_dir = active && result.dir == "asc" ? "desc" : "asc"

      th do
        a(href: ledger_path(result.to_params.merge(sort: key, dir: next_dir, page: nil).compact)) do
          hstack(spacing: 4, alignment: :center) do
            text(label)
            if active
              icon(result.dir == "asc" ? "arrow_up" : "arrow_down", size: 12)
                .tw("text-slate-950")
            end
          end
        end.tw("group inline-flex items-center gap-1 font-black uppercase tracking-widest text-xs #{active ? 'text-slate-950' : 'text-slate-400 hover:text-slate-700'}")
      end.tw("px-5 py-3.5")
    end

    def ledger_row(row)
      tr do
        td(row.id).tw("px-5 py-3 font-mono text-xs font-bold text-slate-500")
        td(row.customer).tw("px-5 py-3 font-bold text-slate-950")
        td do
          span(row.status.capitalize)
            .tw("rounded-full px-3 py-1 text-xs font-black uppercase tracking-widest #{STATUS_BADGES.fetch(row.status)}")
        end.tw("px-5 py-3")
        td(row.amount).tw("px-5 py-3 font-mono text-sm text-slate-700")
        td(row.issued_on.strftime("%b %-d, %Y")).tw("px-5 py-3 text-slate-500")
      end.tw("transition hover:bg-slate-50")
    end

    def pagination_bar
      hstack(spacing: 8, alignment: :center) do
        if result.page > 1
          page_link("← Previous", result.page - 1)
        end

        text("Page #{result.page} of #{result.total_pages}")
          .tw("text-sm font-bold text-slate-500")

        if result.page < result.total_pages
          page_link("Next →", result.page + 1)
        end
      end
    end

    def page_link(label, page)
      a(label, href: ledger_path(result.to_params.merge(page: page)))
        .tw("rounded-full bg-white px-5 py-2.5 text-sm font-black text-slate-950 shadow ring-1 ring-slate-900/10 transition hover:bg-slate-100")
    end

    def summary_line
      "#{result.total_count} invoices" \
        "#{result.q.present? ? " matching “#{result.q}”" : ''}" \
        "#{result.status.present? ? " · #{result.status}" : ''}"
    end

    def ledger_path(params = {})
      helpers.demos_ledger_path(**params.symbolize_keys)
    end
  end
end
