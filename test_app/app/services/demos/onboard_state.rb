# frozen_string_literal: true

module Demos
  # Session-backed wizard state. Steps are URL-addressable (?step=n); a step
  # only advances when its fields validate, and later steps cannot be reached
  # until every earlier step is complete — deep links clamp back to the first
  # incomplete step.
  class OnboardState
    STEPS = [
      { key: "profile", title: "Profile", fields: %i[full_name role] },
      { key: "workspace", title: "Workspace", fields: %i[team_name team_size] },
      { key: "notifications", title: "Notifications", fields: %i[digest] },
      { key: "review", title: "Review", fields: [] }
    ].freeze

    ROLES = ["Engineer", "Designer", "Product", "Operations"].freeze
    TEAM_SIZES = ["Just me", "2-10", "11-50", "51+"].freeze
    DIGESTS = %w[daily weekly off].freeze

    attr_reader :values

    def initialize(stored = nil)
      stored = {} unless stored.is_a?(Hash)
      @values = {
        "full_name" => stored["full_name"].to_s.first(80),
        "role" => ROLES.include?(stored["role"]) ? stored["role"] : "",
        "team_name" => stored["team_name"].to_s.first(80),
        "team_size" => TEAM_SIZES.include?(stored["team_size"]) ? stored["team_size"] : "",
        "digest" => DIGESTS.include?(stored["digest"]) ? stored["digest"] : "weekly",
        "completed" => stored["completed"] == true
      }
    end

    def to_h
      @values.dup
    end

    def completed?
      @values.fetch("completed")
    end

    # 1-based index of the furthest step the user may visit.
    def furthest_step
      return 1 if @values["full_name"].blank? || @values["role"].blank?
      return 2 if @values["team_name"].blank? || @values["team_size"].blank?

      # Digest always has a valid default, so notifications never blocks review.
      STEPS.length
    end

    def clamp_step(requested)
      candidate = Integer(requested.to_s, exception: false) || 1
      candidate.clamp(1, furthest_step)
    end

    # Applies a step's submitted fields. Returns an error message when the
    # step is invalid, nil on success.
    def apply_step!(step_number, params)
      step = STEPS[step_number - 1] or return "Unknown step"
      # Defense in depth: never let a direct submission jump ahead of the
      # furthest reachable step (e.g. mark an empty wizard complete via step=4).
      return "Complete earlier steps first" if step_number > furthest_step

      step[:fields].each do |field|
        raw = params[field].to_s.strip
        case field
        when :full_name, :team_name
          return "#{field.to_s.humanize} is required" if raw.blank?

          @values[field.to_s] = raw.first(80)
        when :role
          return "Pick a role" unless ROLES.include?(raw)

          @values["role"] = raw
        when :team_size
          return "Pick a team size" unless TEAM_SIZES.include?(raw)

          @values["team_size"] = raw
        when :digest
          return "Pick a digest cadence" unless DIGESTS.include?(raw)

          @values["digest"] = raw
        end
      end

      @values["completed"] = true if step[:key] == "review"
      nil
    end

    def reset!
      @values = OnboardState.new(nil).values
      self
    end
  end
end
