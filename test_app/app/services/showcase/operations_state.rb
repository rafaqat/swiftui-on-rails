# frozen_string_literal: true

module Showcase
  class OperationsState
    EVENT_TYPES = %w[deploy incident recover scale heartbeat].freeze
    SERVICE_IDS = %w[api jobs search].freeze
    MAX_ACTIVITY = 10

    DEFAULT_SERVICES = {
      "api" => {
        "name" => "Public API",
        "status" => "operational",
        "version" => "2.8.0",
        "latency" => 84,
        "capacity" => 72
      },
      "jobs" => {
        "name" => "Background Jobs",
        "status" => "operational",
        "version" => "1.14.2",
        "latency" => 126,
        "capacity" => 58
      },
      "search" => {
        "name" => "Search Cluster",
        "status" => "operational",
        "version" => "4.3.1",
        "latency" => 47,
        "capacity" => 64
      }
    }.freeze

    attr_reader :services, :activity, :deployments, :incidents

    def initialize(attributes = nil, clock: -> { Time.current })
      @clock = clock
      source = attributes.is_a?(Hash) ? attributes.deep_stringify_keys : {}
      @services = normalize_services(source["services"])
      @activity = normalize_activity(source["activity"])
      @deployments = bounded_integer(source["deployments"], default: 14, maximum: 99_999)
      @incidents = bounded_integer(source["incidents"], default: 0, maximum: 99_999)
    end

    def apply!(event_type, service_id: nil)
      event = event_type.to_s
      raise ArgumentError, "Unsupported operations event" unless EVENT_TYPES.include?(event)

      service = resolve_service!(service_id || "api")

      case event
      when "deploy"
        service["version"] = increment_patch(service["version"])
        service["status"] = "deploying"
        @deployments += 1
        record("Deployment #{service["version"]} started", service)
      when "incident"
        service["status"] = "degraded"
        service["latency"] = [service["latency"] * 3, 9_999].min
        @incidents += 1
        record("Latency incident detected", service, severity: "critical")
      when "recover"
        service["status"] = "operational"
        service["latency"] = baseline_latency(service_id)
        record("Service recovered", service, severity: "success")
      when "scale"
        service["capacity"] = [service["capacity"] + 10, 100].min
        record("Capacity increased to #{service["capacity"]}%", service)
      when "heartbeat"
        service["status"] = "operational" if service["status"] == "deploying"
        service["latency"] = heartbeat_latency(service)
        record("Health check completed in #{service["latency"]} ms", service)
      end

      self
    end

    def summary
      {
        operational: services.values.count { |service| service["status"] == "operational" },
        total: services.length,
        average_latency: (services.values.sum { |service| service["latency"] } / services.length.to_f).round,
        deployments: deployments,
        incidents: incidents
      }
    end

    def to_h
      {
        "services" => services.deep_dup,
        "activity" => activity.map(&:dup),
        "deployments" => deployments,
        "incidents" => incidents
      }
    end

    private

    def normalize_services(value)
      supplied = value.is_a?(Hash) ? value.deep_stringify_keys : {}

      DEFAULT_SERVICES.each_with_object({}) do |(id, defaults), normalized|
        candidate = supplied[id].is_a?(Hash) ? supplied[id] : {}
        candidate = candidate.deep_stringify_keys
        normalized[id] = {
          "name" => defaults["name"],
          "status" => %w[operational degraded deploying].include?(candidate["status"]) ? candidate["status"] : defaults["status"],
          "version" => candidate["version"].to_s.match?(/\A\d+\.\d+\.\d+\z/) ? candidate["version"] : defaults["version"],
          "latency" => bounded_integer(candidate["latency"], default: defaults["latency"], maximum: 9_999),
          "capacity" => bounded_integer(candidate["capacity"], default: defaults["capacity"], maximum: 100)
        }
      end
    end

    def normalize_activity(value)
      return default_activity unless value.is_a?(Array)

      value.first(MAX_ACTIVITY).filter_map do |entry|
        next unless entry.is_a?(Hash)

        entry = entry.deep_stringify_keys
        service_id = entry["service_id"].to_s
        next unless SERVICE_IDS.include?(service_id)

        {
          "message" => entry["message"].to_s.first(120),
          "service_id" => service_id,
          "service_name" => DEFAULT_SERVICES.fetch(service_id).fetch("name"),
          "severity" => %w[info success critical].include?(entry["severity"]) ? entry["severity"] : "info",
          "timestamp" => entry["timestamp"].to_s.first(40)
        }
      end
    end

    def default_activity
      [
        {
          "message" => "All systems passed the release health check",
          "service_id" => "api",
          "service_name" => "Public API",
          "severity" => "success",
          "timestamp" => timestamp
        }
      ]
    end

    def resolve_service!(service_id)
      id = service_id.to_s
      raise ArgumentError, "Unknown service" unless SERVICE_IDS.include?(id)

      services.fetch(id)
    end

    def record(message, service, severity: "info")
      service_id = services.key(service)
      activity.unshift(
        "message" => message,
        "service_id" => service_id,
        "service_name" => service.fetch("name"),
        "severity" => severity,
        "timestamp" => timestamp
      )
      activity.slice!(MAX_ACTIVITY, activity.length)
    end

    def timestamp
      @clock.call.iso8601
    end

    def increment_patch(version)
      major, minor, patch = version.to_s.split(".").map(&:to_i)
      [major, minor, patch + 1].join(".")
    end

    def baseline_latency(service_id)
      DEFAULT_SERVICES.fetch(service_id.to_s).fetch("latency")
    end

    def heartbeat_latency(service)
      baseline = baseline_latency(services.key(service))
      drift = (activity.length * 7 + deployments) % 23
      baseline + drift
    end

    def bounded_integer(value, default:, maximum:)
      integer = Integer(value, exception: false)
      return default unless integer

      integer.clamp(0, maximum)
    end
  end
end
