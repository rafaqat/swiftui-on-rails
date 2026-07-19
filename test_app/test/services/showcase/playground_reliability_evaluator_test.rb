# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class ReliabilityEvaluatorTest < ActiveSupport::TestCase
      setup do
        @view_context = ApplicationController.new.view_context
      end

      test "corpus fixes the required reliability categories and repair artifacts" do
        assert_equal ReliabilityCorpus.all.map(&:id).uniq.sort, ReliabilityCorpus.all.map(&:id).sort
        assert_includes ReliabilityCorpus.categories, "valid_generation"
        assert_includes ReliabilityCorpus.categories, "invalid_nesting"
        assert_includes ReliabilityCorpus.categories, "identity"
        assert_includes ReliabilityCorpus.categories, "security_adversarial"
        assert_includes ReliabilityCorpus.categories, "repair"
        assert_includes ReliabilityCorpus.categories, "accessibility"

        rejected = ReliabilityCorpus.all.reject { |entry| entry.expect == "accept" }
        assert rejected.all? { |entry| entry.diagnostic_codes.any? }
        assert rejected.all?(&:repair?)
        assert ReliabilityCorpus.find("semantic-generation").accessibility?
        assert ReliabilityCorpus.all.frozen?
        assert ReliabilityCorpus.all.all?(&:frozen?)
        assert ReliabilityCorpus.all.all? { |entry| entry.source.frozen? && entry.diagnostic_codes.frozen? }
      end

      test "evaluates acceptance rejection identity security and repairs through the real runner" do
        report = ReliabilityEvaluator.call(view_context: @view_context)

        assert report.success?, report.results.flat_map(&:failures).join("\n")
        assert_equal 9, report.metrics.fetch(:total)
        assert_equal 9, report.metrics.fetch(:passed)
        assert_equal 1.0, report.metrics.fetch(:expectation_rate)
        assert_equal "recorded_candidate_language_conformance", report.metrics.fetch(:measurement_scope)
        assert_equal "not_run_without_provider", report.metrics.fetch(:model_prompt_execution)
        assert_equal 2, report.metrics.fetch(:recorded_valid_cases)
        assert_equal 2, report.metrics.fetch(:recorded_candidates_valid)
        assert_equal 1.0, report.metrics.fetch(:recorded_candidate_validity_rate)
        assert_nil report.metrics.fetch(:model_first_pass_validity_rate)
        assert_equal 7, report.metrics.fetch(:golden_repair_cases)
        assert_equal 1.0, report.metrics.fetch(:semantic_snapshot_accuracy)
        assert_equal 2, report.metrics.fetch(:semantic_snapshot_cases)
        assert_equal 2, report.metrics.fetch(:semantic_snapshots_passed)
        assert_equal 2, report.metrics.fetch(:accessibility_cases)
        assert_equal 2, report.metrics.fetch(:accessibility_passed)
        assert_equal 1.0, report.metrics.fetch(:accessibility_rate)
        assert_equal 7, report.metrics.fetch(:golden_repairs_checked)
        assert_equal 7, report.metrics.fetch(:golden_repairs_passed)
        assert_equal 1.0, report.metrics.fetch(:golden_repair_contract_rate)
        assert_nil report.metrics.fetch(:model_repair_rate)
        assert_equal 2, report.metrics.fetch(:unsafe_construct_cases)
        assert_equal 2, report.metrics.fetch(:unsafe_constructs_rejected)
        assert_equal 1.0, report.metrics.fetch(:unsafe_construct_rejection_rate)
        assert_equal 2, report.metrics.fetch(:security_rejections)

        efficiency = report.metrics.fetch(:context_efficiency)
        assert efficiency.fetch(:passed)
        assert efficiency.fetch(:executable_constraints_preserved)
        assert_empty efficiency.fetch(:omitted_executable_constraints)
        assert_operator efficiency.fetch(:compact_generation_context_bytes), :<, efficiency.fetch(:full_catalog_bytes)
        assert_operator efficiency.fetch(:bytes_saved), :>, 0
        assert_operator efficiency.fetch(:byte_reduction_rate), :>, 0.5
        assert_operator efficiency.fetch(:compact_generation_context_estimated_tokens), :<, efficiency.fetch(:full_catalog_estimated_tokens)
        assert_operator efficiency.fetch(:estimated_tokens_saved), :>, 0
        assert_equal "ceil(bytes/4)", efficiency.fetch(:token_estimate_method)

        duplicate = report.results.find { |result| result.id == "duplicate-runtime-identity" }
        assert_includes duplicate.diagnostic_codes, "duplicate_id"
        assert duplicate.repair_passed
      end

      test "reports deterministic expectation and repair failures" do
        benchmark = ReliabilityCorpus::Case.new(
          id: "deliberate-failure",
          category: "repair",
          prompt: "test",
          source: 'text("valid")',
          data_json: "{}",
          expect: "reject",
          diagnostic_codes: [ "made_up" ],
          repair_source: 'system("still invalid")'
        )

        report = ReliabilityEvaluator.call(view_context: @view_context, cases: [ benchmark ])
        result = report.results.first

        assert_not report.success?
        assert_not result.passed
        assert result.accepted
        assert_not result.repair_passed
        assert_includes result.failures, "expected reject, got accept"
        assert_includes result.failures, "missing diagnostic codes: made_up"
        assert_match(/repair was rejected/, result.failures.last)
      end

      test "does not report a vacuous pass or perfect rates for an empty corpus" do
        report = ReliabilityEvaluator.call(view_context: @view_context, cases: [])

        assert_not report.success?
        assert_equal 0, report.metrics.fetch(:total)
        assert_nil report.metrics.fetch(:expectation_rate)
        assert_nil report.metrics.fetch(:recorded_candidate_validity_rate)
        assert_nil report.metrics.fetch(:golden_repair_contract_rate)
        assert_nil report.metrics.fetch(:semantic_snapshot_accuracy)
        assert_nil report.metrics.fetch(:accessibility_rate)
        assert_nil report.metrics.fetch(:unsafe_construct_rejection_rate)
      end

      test "requires golden repairs to preserve declared semantic intent" do
        benchmark = ReliabilityCorpus::Case.new(
          id: "unrelated-repair",
          category: "repair",
          prompt: "Preserve the release title",
          source: 'system("invalid")',
          data_json: "{}",
          expect: "reject",
          diagnostic_codes: [ "unknown_view" ],
          repair_source: 'text("Unrelated")',
          repair_html_includes: [ "Release" ]
        )

        report = ReliabilityEvaluator.call(view_context: @view_context, cases: [ benchmark ])
        result = report.results.first

        assert_not report.success?
        assert_not result.repair_passed
        assert_includes result.failures, "golden repair missed intent fragments: Release"
        assert_equal 0.0, report.metrics.fetch(:golden_repair_contract_rate)
      end

      test "fails explicit accessibility expectations instead of treating valid HTML as accessible" do
        benchmark = ReliabilityCorpus::Case.new(
          id: "missing-status-semantics",
          category: "valid_generation",
          prompt: "Show a status",
          source: 'text("Operational")',
          data_json: "{}",
          expect: "accept",
          diagnostic_codes: [],
          html_includes: [ "Operational" ],
          html_excludes: [],
          accessibility_includes: [ 'role="status"' ],
          accessibility_excludes: []
        )

        report = ReliabilityEvaluator.call(view_context: @view_context, cases: [ benchmark ])
        result = report.results.first

        assert_not report.success?
        assert result.accepted
        assert result.semantic_snapshot_passed
        assert result.accessibility_required
        assert_not result.accessibility_passed
        assert_equal 0.0, report.metrics.fetch(:accessibility_rate)
        assert_includes result.failures, 'missing accessibility fragments: role="status"'
      end
    end
  end
end
