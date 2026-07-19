# frozen_string_literal: true

# The /demos gallery. Filtering is URL-driven on purpose — the filter chips
# are plain GET links and the selected model lives in params, so the page is
# shareable, back-button friendly, and works without JavaScript.
class DemosController < ApplicationController
  def index
    @selected_model = DemoCatalog::INTERACTION_MODELS.key?(params[:model].to_s.to_sym) ? params[:model].to_s.to_sym : nil
    @demos = @selected_model ? DemoCatalog.filtered(@selected_model) : DemoCatalog.entries
  end
end
