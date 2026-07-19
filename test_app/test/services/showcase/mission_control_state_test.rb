# frozen_string_literal: true

require "test_helper"
require "json"

class Showcase::MissionControlStateTest < ActiveSupport::TestCase
  setup do
    @clock = -> { Time.zone.parse("2026-07-18 12:00:00") }
    @state = Showcase::MissionControlState.new(nil, clock: @clock)
  end

  test "starts from a versioned normalized mission baseline" do
    assert_equal %w[weather payload propellant guidance range], @state.order
    assert_equal "hold", @state.systems.fetch("range")
    assert_equal({ "winds" => "open", "handoff" => "open" }, @state.alerts)
    assert_equal "T−12", @state.phase.fetch("code")
    assert_equal "HOLD", @state.mission_status
    assert_equal Showcase::MissionControlState::STATE_VERSION, @state.to_h.fetch("version")
  end

  test "normalizes every session-owned collection and rejects a stale schema" do
    stale = Showcase::MissionControlState.new(
      {
        version: 99,
        order: %w[range guidance propellant payload weather],
        systems: { range: "go" },
        phase_index: 99
      },
      clock: @clock
    )
    assert_equal Showcase::MissionControlState::SEQUENCE.keys, stale.order
    assert_equal "hold", stale.systems.fetch("range")
    assert_equal 1, stale.phase_index

    restored = Showcase::MissionControlState.new(
      {
        version: Showcase::MissionControlState::STATE_VERSION,
        order: %w[range guidance propellant payload weather],
        systems: { propulsion: "owned", guidance: "hold", attacker: "go" },
        alerts: { winds: "escalated", handoff: "eval", attacker: "open" },
        phase_index: 99,
        activity: Array.new(20) do |index|
          { message: "Verified event #{index}", tone: "success", timestamp: "2026-07-18T12:00:00Z" }
        end
      },
      clock: @clock
    )

    assert_equal %w[range guidance propellant payload weather], restored.order
    assert_equal Showcase::MissionControlState::SYSTEMS.keys, restored.systems.keys
    assert_equal "go", restored.systems.fetch("propulsion")
    assert_equal "hold", restored.systems.fetch("guidance")
    assert_equal Showcase::MissionControlState::ALERTS.keys, restored.alerts.keys
    assert_equal "escalated", restored.alerts.fetch("winds")
    assert_equal "open", restored.alerts.fetch("handoff")
    assert_equal Showcase::MissionControlState::PHASES.length - 1, restored.phase_index
    assert_equal Showcase::MissionControlState::MAX_ACTIVITY, restored.activity.length
  end

  test "a corrupted session filename cannot brick restoration" do
    state = nil
    assert_nothing_raised do
      state = Showcase::MissionControlState.new(
        {
          version: Showcase::MissionControlState::STATE_VERSION,
          document: {
            filename: "\0C:\\untrusted\\flight-plan.pdf",
            bytes: 420,
            source: "import"
          }
        },
        clock: @clock
      )
    end

    assert_equal "flight-plan.pdf", state.document.fetch("filename")
    assert_equal 420, state.document.fetch("bytes")
  end

  test "document envelopes are harmless bounded session metadata" do
    @state.record_document!(
      filename: "../../payload\0-brief.txt",
      bytes: Showcase::MissionControlState::MAX_DOCUMENT_BYTES,
      source: :template
    )

    assert_equal "payload-brief.txt", @state.document.fetch("filename")
    assert_equal Showcase::MissionControlState::MAX_DOCUMENT_BYTES, @state.document.fetch("bytes")
    assert_equal "template", @state.document.fetch("source")

    assert_raises(ArgumentError) do
      @state.record_document!(filename: "plan.txt", bytes: 1, source: "remote")
    end
    assert_raises(ArgumentError) do
      @state.record_document!(filename: "plan.txt", bytes: 1.megabyte + 1, source: "import")
    end
    assert_raises(ArgumentError) do
      @state.record_document!(filename: "plan.txt", bytes: 1.5, source: "import")
    end
  end

  test "reordering commands and count interlocks use fixed allowlists" do
    @state.move!(item_key: "range", target_key: "payload", placement: "before")
    assert_equal %w[weather range payload propellant guidance], @state.order

    assert_raises(ArgumentError) do
      @state.move!(item_key: "Kernel", direction: "up")
    end
    assert_raises(ArgumentError) do
      @state.update_system!("Object", "go")
    end
    assert_raises(ArgumentError) do
      @state.update_alert!("winds", "constantize")
    end

    assert_raises(Showcase::MissionControlState::InterlockError) { @state.advance! }
    @state.update_system!("range", "go")
    @state.update_alert!("winds", "escalate")
    assert_raises(Showcase::MissionControlState::InterlockError) { @state.advance! }
    @state.update_alert!("winds", "acknowledge")
    @state.advance!
    assert_equal "T−04", @state.phase.fetch("code")
  end

  test "the worst normalized state remains small and activity stays bounded" do
    state = Showcase::MissionControlState.new(
      {
        version: Showcase::MissionControlState::STATE_VERSION,
        activity: Array.new(Showcase::MissionControlState::MAX_ACTIVITY) do
          {
            message: "x" * Showcase::MissionControlState::MAX_ACTIVITY_MESSAGE_BYTES,
            tone: "critical",
            timestamp: "2026-07-18T12:00:00.000000Z"
          }
        end,
        document: {
          filename: "x" * Showcase::MissionControlState::MAX_FILENAME_BYTES,
          bytes: Showcase::MissionControlState::MAX_DOCUMENT_BYTES,
          source: "generated"
        }
      },
      clock: @clock
    )

    assert_operator JSON.generate(state.to_h).bytesize, :<, 2.kilobytes
    state.update_system!("range", "go")
    assert_equal Showcase::MissionControlState::MAX_ACTIVITY, state.activity.length
  end
end
