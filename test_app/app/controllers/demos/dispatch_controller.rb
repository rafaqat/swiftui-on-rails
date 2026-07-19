# frozen_string_literal: true

module Demos
  # Dispatch: station selection is URL state and the map is server-rendered.
  class DispatchController < BaseController
    def show
      @stations = Demos::DispatchNetwork.stations
      @selected = Demos::DispatchNetwork.find(params[:station])
    end
  end
end
