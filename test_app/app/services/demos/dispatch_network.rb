# frozen_string_literal: true

module Demos
  # Fixed station data for the Dispatch map demo.
  class DispatchNetwork
    Station = Data.define(:id, :name, :latitude, :longitude, :status, :detail)

    STATIONS = [
      Station.new(id: "north-relay", name: "North Relay", latitude: 51.62, longitude: -0.18,
                  status: "online", detail: "Primary uplink · 42 ms round trip · 3 couriers docked"),
      Station.new(id: "river-dock", name: "River Dock", latitude: 51.48, longitude: -0.05,
                  status: "online", detail: "Freight staging · 12 pallets queued · crane nominal"),
      Station.new(id: "west-yard", name: "West Yard", latitude: 51.51, longitude: -0.35,
                  status: "degraded", detail: "Reduced throughput · generator maintenance until 16:00"),
      Station.new(id: "south-gate", name: "South Gate", latitude: 51.38, longitude: -0.12,
                  status: "online", detail: "Passenger transfers · 8 min headway · staffed"),
      Station.new(id: "east-annex", name: "East Annex", latitude: 51.53, longitude: 0.09,
                  status: "offline", detail: "Scheduled dark window · reopens 05:00 · alarms quiet")
    ].freeze

    CENTER = [51.5, -0.1].freeze
    SPAN = [0.35, 0.55].freeze

    class << self
      def stations
        STATIONS
      end

      def find(id)
        STATIONS.find { |station| station.id == id.to_s }
      end
    end
  end
end
