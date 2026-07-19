# frozen_string_literal: true

require "test_helper"

class Showcase::OperationsStateTest < ActiveSupport::TestCase
  setup do
    @clock = -> { Time.zone.parse("2026-07-17 12:00:00") }
    @state = Showcase::OperationsState.new(nil, clock: @clock)
  end

  test "starts with a normalized operational service mesh" do
    assert_equal %w[api jobs search], @state.services.keys
    assert_equal 3, @state.summary[:operational]
    assert_equal 14, @state.deployments
    assert_equal 0, @state.incidents
  end

  test "deployment increments the version and audit metrics" do
    @state.apply!("deploy", service_id: "api")

    assert_equal "2.8.1", @state.services.dig("api", "version")
    assert_equal "deploying", @state.services.dig("api", "status")
    assert_equal 15, @state.deployments
    assert_equal "Deployment 2.8.1 started", @state.activity.first["message"]
  end

  test "incident and recovery transitions are bounded and reversible" do
    @state.apply!("incident", service_id: "search")

    assert_equal "degraded", @state.services.dig("search", "status")
    assert_equal 1, @state.incidents
    assert_operator @state.services.dig("search", "latency"), :>, 47

    @state.apply!("recover", service_id: "search")

    assert_equal "operational", @state.services.dig("search", "status")
    assert_equal 47, @state.services.dig("search", "latency")
  end

  test "session input cannot add services or unbounded values" do
    restored = Showcase::OperationsState.new(
      {
        services: {
          api: { status: "owned", latency: 1_000_000, capacity: -20 },
          attacker: { name: "Injected" }
        },
        deployments: 1_000_000,
        activity: [{ service_id: "attacker", message: "Injected" }]
      },
      clock: @clock
    )

    assert_equal %w[api jobs search], restored.services.keys
    assert_equal "operational", restored.services.dig("api", "status")
    assert_equal 9_999, restored.services.dig("api", "latency")
    assert_equal 0, restored.services.dig("api", "capacity")
    assert_equal 99_999, restored.deployments
    assert_empty restored.activity
  end

  test "rejects unknown events and service identifiers" do
    assert_raises(ArgumentError) { @state.apply!("eval", service_id: "api") }
    assert_raises(ArgumentError) { @state.apply!("deploy", service_id: "kernel") }
  end
end
