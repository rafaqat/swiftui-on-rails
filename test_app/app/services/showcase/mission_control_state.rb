# frozen_string_literal: true

module Showcase
  class MissionControlState
    class InterlockError < StandardError; end

    STATE_VERSION = 1
    MAX_ACTIVITY = 6
    MAX_ACTIVITY_MESSAGE_BYTES = 120
    MAX_TIMESTAMP_BYTES = 40
    MAX_FILENAME_BYTES = 120
    MAX_DOCUMENT_BYTES = 1.megabyte
    DOCUMENT_SOURCES = %w[import new template duplicate generated].freeze
    SYSTEM_STATUSES = %w[go hold].freeze
    ALERT_STATUSES = %w[open acknowledged escalated].freeze
    ACTIVITY_TONES = %w[info success warning critical].freeze

    SEQUENCE = {
      "weather" => {
        "title" => "Weather corridor",
        "owner" => "Flight dynamics",
        "detail" => "Validate upper-level winds and recovery visibility."
      },
      "payload" => {
        "title" => "Payload hand-off",
        "owner" => "Payload operations",
        "detail" => "Transfer spacecraft authority to the launch sequencer."
      },
      "propellant" => {
        "title" => "Propellant conditioning",
        "owner" => "Propulsion",
        "detail" => "Confirm tank pressure, temperature, and valve alignment."
      },
      "guidance" => {
        "title" => "Guidance alignment",
        "owner" => "GNC",
        "detail" => "Load the final trajectory and verify inertial alignment."
      },
      "range" => {
        "title" => "Range release",
        "owner" => "Range safety",
        "detail" => "Clear the flight corridor and arm tracking assets."
      }
    }.each_value(&:freeze).freeze

    SYSTEMS = {
      "propulsion" => {
        "name" => "Propulsion",
        "detail" => "Chamber conditioning",
        "metric" => "3.18 MPa"
      },
      "guidance" => {
        "name" => "Guidance",
        "detail" => "Inertial solution",
        "metric" => "0.04°"
      },
      "communications" => {
        "name" => "Communications",
        "detail" => "S-band downlink",
        "metric" => "−71 dBm"
      },
      "range" => {
        "name" => "Range safety",
        "detail" => "Corridor clearance",
        "metric" => "2,140 km"
      }
    }.each_value(&:freeze).freeze

    ALERTS = {
      "winds" => {
        "title" => "Upper-level wind model updated",
        "detail" => "Flight dynamics · 4 minutes ago"
      },
      "handoff" => {
        "title" => "Payload hand-off awaiting voice confirmation",
        "detail" => "Payload operations · 1 minute ago"
      }
    }.each_value(&:freeze).freeze

    PHASES = [
      {
        "code" => "T−45",
        "name" => "Integrated systems check",
        "detail" => "Controllers verify vehicle, payload, range, and weather data."
      },
      {
        "code" => "T−12",
        "name" => "Terminal count setup",
        "detail" => "The launch sequencer assumes authority and closes final constraints."
      },
      {
        "code" => "T−04",
        "name" => "Autosequence",
        "detail" => "Ground systems hand control to the autonomous flight computer."
      },
      {
        "code" => "T+00",
        "name" => "Liftoff",
        "detail" => "Commit criteria are satisfied and ascent guidance is active."
      }
    ].each(&:freeze).freeze

    attr_reader :order, :systems, :alerts, :phase_index, :activity, :document

    def initialize(attributes = nil, clock: -> { Time.current })
      @clock = clock
      source = attributes.is_a?(Hash) ? attributes.deep_stringify_keys : {}
      source = {} unless source["version"] == STATE_VERSION
      @order = normalize_order(source["order"])
      @systems = normalize_systems(source["systems"])
      @alerts = normalize_alerts(source["alerts"])
      @phase_index = bounded_integer(source["phase_index"], default: 1, maximum: PHASES.length - 1)
      @activity = normalize_activity(source["activity"])
      @document = normalize_document(source["document"])
    end

    def move!(item_key:, direction: nil, target_key: nil, placement: nil)
      key = item_key.to_s
      raise ArgumentError, "Unknown mission sequence item" unless SEQUENCE.key?(key)

      destination = if direction.present?
        directional_destination(key, direction.to_s)
      else
        targeted_destination(key, target_key.to_s, placement.to_s)
      end
      raise ArgumentError, "Invalid mission sequence move" unless destination

      @order.delete(key)
      @order.insert(destination.clamp(0, @order.length), key)
      record("#{SEQUENCE.fetch(key).fetch('title')} moved in the launch sequence", tone: "info")
      self
    end

    def update_system!(system_id, action)
      id = system_id.to_s
      command = action.to_s
      raise ArgumentError, "Unknown mission system" unless SYSTEMS.key?(id)
      raise ArgumentError, "Unknown system command" unless SYSTEM_STATUSES.include?(command)

      @systems[id] = command
      verb = command == "go" ? "marked GO" : "placed on HOLD"
      record("#{SYSTEMS.fetch(id).fetch('name')} #{verb}", tone: command == "go" ? "success" : "warning")
      self
    end

    def update_alert!(alert_id, action)
      id = alert_id.to_s
      command = action.to_s
      raise ArgumentError, "Unknown flight alert" unless ALERTS.key?(id)
      raise ArgumentError, "Unknown alert command" unless %w[acknowledge escalate].include?(command)

      @alerts[id] = command == "acknowledge" ? "acknowledged" : "escalated"
      record(
        "#{ALERTS.fetch(id).fetch('title')} #{command}d",
        tone: command == "acknowledge" ? "success" : "critical"
      )
      self
    end

    def advance!
      raise InterlockError, "Resolve every system hold before advancing the count." if hold_count.positive?
      raise InterlockError, "Resolve escalated flight alerts before advancing the count." if escalated_alerts.positive?
      raise InterlockError, "The mission is already at the final phase." if phase_index >= PHASES.length - 1

      @phase_index += 1
      record("Count advanced to #{phase.fetch('code')} · #{phase.fetch('name')}", tone: "success")
      self
    end

    def reset!
      @order = SEQUENCE.keys
      @systems = default_systems
      @alerts = default_alerts
      @phase_index = 1
      @document = nil
      @activity = []
      record("Mission workspace reset to the verified baseline", tone: "info")
      self
    end

    def record_document!(filename:, bytes:, source:)
      safe_source = source.to_s
      unless DOCUMENT_SOURCES.include?(safe_source)
        raise ArgumentError, "Unknown document provenance"
      end

      safe_bytes = strict_bounded_integer(bytes, maximum: MAX_DOCUMENT_BYTES)
      raise ArgumentError, "Invalid document size" unless safe_bytes

      @document = {
        "filename" => safe_filename(filename),
        "bytes" => safe_bytes,
        "source" => safe_source
      }
      record("#{@document.fetch('filename')} verified from #{@document.fetch('source')}", tone: "success")
      self
    end

    def phase
      PHASES.fetch(phase_index)
    end

    def readiness
      ((systems.values.count("go") / systems.length.to_f) * 100).round
    end

    def hold_count
      systems.values.count("hold")
    end

    def escalated_alerts
      alerts.values.count("escalated")
    end

    def mission_status
      hold_count.zero? && escalated_alerts.zero? ? "GO" : "HOLD"
    end

    def sequence_items
      order.each_with_index.map do |key, index|
        definition = SEQUENCE.fetch(key)
        status = if index < phase_index
          "complete"
        elsif index == phase_index
          "active"
        else
          "queued"
        end

        {
          key: key,
          title: definition.fetch("title"),
          owner: definition.fetch("owner"),
          detail: definition.fetch("detail"),
          status: status
        }
      end
    end

    def system_items
      SYSTEMS.map do |id, definition|
        {
          id: id,
          name: definition.fetch("name"),
          detail: definition.fetch("detail"),
          metric: definition.fetch("metric"),
          status: systems.fetch(id)
        }
      end
    end

    def alert_items
      ALERTS.map do |id, definition|
        {
          id: id,
          title: definition.fetch("title"),
          detail: definition.fetch("detail"),
          status: alerts.fetch(id)
        }
      end
    end

    def telemetry
      offset = phase_index * 2
      {
        "T−50" => 72 + offset,
        "T−40" => 78 + offset,
        "T−30" => 76 + offset,
        "T−20" => 84 + offset,
        "T−10" => 88 + offset,
        "Now" => [92 + offset, 100].min
      }
    end

    def to_h
      {
        "version" => STATE_VERSION,
        "order" => order.dup,
        "systems" => systems.dup,
        "alerts" => alerts.dup,
        "phase_index" => phase_index,
        "activity" => activity.map(&:dup),
        "document" => document&.dup
      }
    end

    private

    def normalize_order(value)
      candidate = Array(value).map(&:to_s)
      candidate.sort == SEQUENCE.keys.sort ? candidate : SEQUENCE.keys
    end

    def normalize_systems(value)
      supplied = value.is_a?(Hash) ? value.deep_stringify_keys : {}
      SYSTEMS.each_key.to_h do |id|
        status = supplied[id].to_s
        [id, SYSTEM_STATUSES.include?(status) ? status : default_systems.fetch(id)]
      end
    end

    def normalize_alerts(value)
      supplied = value.is_a?(Hash) ? value.deep_stringify_keys : {}
      ALERTS.each_key.to_h do |id|
        status = supplied[id].to_s
        [id, ALERT_STATUSES.include?(status) ? status : default_alerts.fetch(id)]
      end
    end

    def normalize_activity(value)
      entries = value.is_a?(Array) ? value : default_activity
      entries.first(MAX_ACTIVITY).filter_map do |entry|
        next unless entry.is_a?(Hash)

        candidate = entry.deep_stringify_keys
        tone = candidate["tone"].to_s
        message = bounded_text(candidate["message"], maximum: MAX_ACTIVITY_MESSAGE_BYTES)
        recorded_at = bounded_text(candidate["timestamp"], maximum: MAX_TIMESTAMP_BYTES)
        next unless message && recorded_at

        {
          "message" => message,
          "tone" => ACTIVITY_TONES.include?(tone) ? tone : "info",
          "timestamp" => recorded_at
        }
      end
    end

    def normalize_document(value)
      return unless value.is_a?(Hash)

      candidate = value.deep_stringify_keys
      source = candidate["source"].to_s
      return unless DOCUMENT_SOURCES.include?(source)

      filename = safe_filename(candidate["filename"])
      bytes = strict_bounded_integer(candidate["bytes"], maximum: MAX_DOCUMENT_BYTES)
      return unless bytes

      {
        "filename" => filename,
        "bytes" => bytes,
        "source" => source
      }
    end

    def default_systems
      {
        "propulsion" => "go",
        "guidance" => "go",
        "communications" => "go",
        "range" => "hold"
      }
    end

    def default_alerts
      { "winds" => "open", "handoff" => "open" }
    end

    def default_activity
      [
        {
          "message" => "Atlas flight workspace synchronized with the launch authority",
          "tone" => "success",
          "timestamp" => timestamp
        }
      ]
    end

    def directional_destination(item_key, direction)
      index = order.index(item_key)
      case direction
      when "up" then [index - 1, 0].max
      when "down" then [index + 1, order.length - 1].min
      end
    end

    def targeted_destination(item_key, target_key, placement)
      return unless SEQUENCE.key?(target_key) && target_key != item_key
      return unless %w[before after].include?(placement)

      reduced = order - [item_key]
      target_index = reduced.index(target_key)
      target_index + (placement == "after" ? 1 : 0)
    end

    def record(message, tone:)
      safe_message = truncate_text(message, maximum: MAX_ACTIVITY_MESSAGE_BYTES)
      activity.unshift(
        "message" => safe_message,
        "tone" => ACTIVITY_TONES.include?(tone) ? tone : "info",
        "timestamp" => timestamp
      )
      activity.slice!(MAX_ACTIVITY, activity.length)
    end

    def timestamp
      @clock.call.iso8601
    end

    def bounded_integer(value, default:, maximum:)
      integer = Integer(value, exception: false)
      return default unless integer

      integer.clamp(0, maximum)
    end

    def strict_bounded_integer(value, maximum:)
      integer = if value.is_a?(Integer)
        value
      elsif value.is_a?(String) && value.match?(/\A\d+\z/)
        value.to_i
      end
      integer if integer&.between?(0, maximum)
    end

    def safe_filename(value)
      filename = value.to_s
      filename = filename.scrub("") unless filename.valid_encoding?
      filename = filename.delete("\0").tr("\\", "/")
      filename = filename.split("/").reject(&:empty?).last.to_s
      filename = filename.gsub(/[\u0000-\u001f\u007f]/, "").strip
      filename = "mission-document" if filename.empty? || %w[. ..].include?(filename)
      truncate_text(filename, maximum: MAX_FILENAME_BYTES)
    end

    def bounded_text(value, maximum:)
      text = value.to_s
      return unless text.valid_encoding? && text.bytesize.between?(1, maximum)
      return if text.match?(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/)

      text
    end

    def truncate_text(value, maximum:)
      text = value.to_s
      return "Mission activity updated" unless text.valid_encoding?

      output = +""
      text.each_char do |character|
        break if output.bytesize + character.bytesize > maximum

        output << character
      end
      output.presence || "Mission activity updated"
    end
  end
end
