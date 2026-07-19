# frozen_string_literal: true

module Demos
  # Ledger owns the :url interaction model — the controller is a single GET
  # that translates params into a page of rows. There are no mutating verbs;
  # the URL is the entire application state.
  class LedgerController < BaseController
    def show
      @result = Demos::LedgerQuery.call(params)
    end
  end
end
