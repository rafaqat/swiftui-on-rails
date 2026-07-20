# frozen_string_literal: true

module Demos
  # Pure translation of URL params into a page of ledger rows. Every value is
  # sanitized against an allowlist — an unknown sort column, direction, or
  # status silently falls back to the default rather than erroring, because
  # URLs are user-editable input.
  class LedgerQuery
    PER_PAGE = 25
    SORTS = {
      "id" => ->(row) { row.id },
      "customer" => ->(row) { row.customer },
      "status" => ->(row) { row.status },
      "amount" => ->(row) { row.amount_cents },
      "issued_on" => ->(row) { row.issued_on }
    }.freeze
    DIRECTIONS = %w[asc desc].freeze

    Result = Data.define(:rows, :page, :total_pages, :total_count, :q, :status, :sort, :dir) do
      def to_params
        {
          q: q.presence,
          status: status.presence,
          sort: sort == "id" ? nil : sort,
          dir: dir == "asc" ? nil : dir
        }.compact
      end
    end

    def self.call(params)
      q = params[:q].to_s.strip.first(80)
      status = LedgerDataset::STATUSES.include?(params[:status].to_s) ? params[:status].to_s : ""
      sort = SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : "id"
      dir = DIRECTIONS.include?(params[:dir].to_s) ? params[:dir].to_s : "asc"

      rows = LedgerDataset.rows
      if q.present?
        needle = q.downcase
        rows = rows.select do |row|
          row.customer.downcase.include?(needle) || row.id.downcase.include?(needle)
        end
      end
      rows = rows.select { |row| row.status == status } if status.present?

      rows = rows.sort_by(&SORTS.fetch(sort))
      rows = rows.reverse if dir == "desc"

      total_count = rows.length
      total_pages = [(total_count / PER_PAGE.to_f).ceil, 1].max
      page = params[:page].to_i.clamp(1, total_pages)

      Result.new(
        rows: rows.slice((page - 1) * PER_PAGE, PER_PAGE) || [],
        page: page,
        total_pages: total_pages,
        total_count: total_count,
        q: q,
        status: status,
        sort: sort,
        dir: dir
      )
    end
  end
end
