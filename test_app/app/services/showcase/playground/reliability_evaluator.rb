# frozen_string_literal: true

require "json"

module Showcase
  module Playground
    # Executes the fixed reliability corpus through the same Runner used by the
    # preview. The runner can be injected, keeping the benchmark deterministic
    # and making it suitable for local tests or a future model-evaluation job.
    class ReliabilityEvaluator
      CaseResult = Struct.new(
        :id,
        :category,
        :passed,
        :accepted,
        :expected_acceptance,
        :diagnostic_codes,
        :semantic_snapshot_required,
        :semantic_snapshot_passed,
        :accessibility_required,
        :accessibility_passed,
        :unsafe_construct_rejected,
        :repair_attempted,
        :repair_passed,
        :failures,
        keyword_init: true
      ) do
        def as_json(*)
          to_h
        end
      end

      Report = Struct.new(:results, :context_efficiency, keyword_init: true) do
        def success?
          results.any? && results.all?(&:passed) && context_efficiency.fetch(:passed)
        end

        def metrics
          repairs = results.select(&:repair_attempted)
          valid_cases = results.select(&:expected_acceptance)
          snapshots = results.select(&:semantic_snapshot_required)
          accessibility = results.select(&:accessibility_required)
          unsafe_constructs = results.select { |result| result.category == "security_adversarial" }
          {
            measurement_scope: "recorded_candidate_language_conformance",
            model_prompt_execution: "not_run_without_provider",
            total: results.length,
            passed: results.count(&:passed),
            expectation_rate: ratio(results.count(&:passed), results.length),
            recorded_acceptances: results.count(&:accepted),
            recorded_valid_cases: valid_cases.length,
            recorded_candidates_valid: valid_cases.count(&:accepted),
            recorded_candidate_validity_rate: ratio(valid_cases.count(&:accepted), valid_cases.length),
            golden_repair_cases: repairs.length,
            golden_repairs_checked: repairs.length,
            golden_repairs_passed: repairs.count(&:repair_passed),
            golden_repair_contract_rate: ratio(repairs.count(&:repair_passed), repairs.length),
            model_first_pass_validity_rate: nil,
            model_repair_rate: nil,
            semantic_snapshot_cases: snapshots.length,
            semantic_snapshots_passed: snapshots.count(&:semantic_snapshot_passed),
            semantic_snapshot_accuracy: ratio(snapshots.count(&:semantic_snapshot_passed), snapshots.length),
            accessibility_cases: accessibility.length,
            accessibility_passed: accessibility.count(&:accessibility_passed),
            accessibility_rate: ratio(accessibility.count(&:accessibility_passed), accessibility.length),
            unsafe_construct_cases: unsafe_constructs.length,
            unsafe_constructs_rejected: unsafe_constructs.count(&:unsafe_construct_rejected),
            unsafe_construct_rejection_rate: ratio(unsafe_constructs.count(&:unsafe_construct_rejected), unsafe_constructs.length),
            security_rejections: unsafe_constructs.count(&:unsafe_construct_rejected),
            context_efficiency: context_efficiency
          }
        end

        def as_json(*)
          {
            ok: success?,
            metrics: metrics,
            results: results.map(&:as_json)
          }
        end

        private

        def ratio(numerator, denominator)
          return if denominator.zero?

          (numerator.to_f / denominator).round(4)
        end
      end

      class << self
        def call(view_context:, cases: ReliabilityCorpus.all, runner: Runner, catalog: LanguageCatalog, assistant_contract: AssistantContract)
          new(
            view_context: view_context,
            cases: cases,
            runner: runner,
            catalog: catalog,
            assistant_contract: assistant_contract
          ).call
        end
      end

      def initialize(view_context:, cases:, runner:, catalog:, assistant_contract:)
        @view_context = view_context
        @cases = cases
        @runner = runner
        @catalog = catalog
        @assistant_contract = assistant_contract
      end

      def call
        results = @cases.map { |benchmark| evaluate(benchmark) }.freeze
        Report.new(results: results, context_efficiency: context_efficiency).freeze
      end

      private

      def evaluate(benchmark)
        first = run(benchmark.source, benchmark.data_json)
        accepted = first.success?
        codes = diagnostic_codes(first)
        failures = []

        expected_acceptance = benchmark.expect == "accept"
        failures << "expected #{benchmark.expect}, got #{accepted ? 'accept' : 'reject'}" unless accepted == expected_acceptance

        missing_codes = benchmark.diagnostic_codes - codes
        failures << "missing diagnostic codes: #{missing_codes.join(', ')}" if missing_codes.any?

        html = first.html.to_s
        missing_html = Array(benchmark.html_includes).reject { |fragment| html.include?(fragment) }
        unexpected_html = Array(benchmark.html_excludes).select { |fragment| html.include?(fragment) }
        semantic_snapshot_required = expected_acceptance && (Array(benchmark.html_includes).any? || Array(benchmark.html_excludes).any?)
        semantic_snapshot_passed = semantic_snapshot_required ? missing_html.empty? && unexpected_html.empty? : nil
        failures << "missing HTML fragments: #{missing_html.join(', ')}" if missing_html.any?
        failures << "unexpected HTML fragments: #{unexpected_html.join(', ')}" if unexpected_html.any?

        missing_accessibility = Array(benchmark.accessibility_includes).reject { |fragment| html.include?(fragment) }
        unexpected_accessibility = Array(benchmark.accessibility_excludes).select { |fragment| html.include?(fragment) }
        accessibility_required = benchmark.accessibility?
        accessibility_passed = accessibility_required ? missing_accessibility.empty? && unexpected_accessibility.empty? : nil
        failures << "missing accessibility fragments: #{missing_accessibility.join(', ')}" if missing_accessibility.any?
        failures << "unexpected accessibility fragments: #{unexpected_accessibility.join(', ')}" if unexpected_accessibility.any?

        unsafe_construct = benchmark.category == "security_adversarial"
        unsafe_construct_rejected = unsafe_construct ? !accepted && missing_codes.empty? && unexpected_html.empty? : nil

        repair_attempted = benchmark.repair?
        repair_passed = nil
        if repair_attempted
          repaired = run(
            benchmark.repair_source || benchmark.source,
            benchmark.repair_data_json || benchmark.data_json
          )
          missing_repair_html = Array(benchmark.repair_html_includes).reject { |fragment| repaired.html.to_s.include?(fragment) }
          unexpected_repair_html = Array(benchmark.repair_html_excludes).select { |fragment| repaired.html.to_s.include?(fragment) }
          repair_passed = repaired.success? && missing_repair_html.empty? && unexpected_repair_html.empty?
          failures << "golden repair was rejected: #{diagnostic_codes(repaired).join(', ')}" unless repaired.success?
          failures << "golden repair missed intent fragments: #{missing_repair_html.join(', ')}" if missing_repair_html.any?
          failures << "golden repair emitted forbidden fragments: #{unexpected_repair_html.join(', ')}" if unexpected_repair_html.any?
        end

        CaseResult.new(
          id: benchmark.id,
          category: benchmark.category,
          passed: failures.empty?,
          accepted: accepted,
          expected_acceptance: expected_acceptance,
          diagnostic_codes: codes.freeze,
          semantic_snapshot_required: semantic_snapshot_required,
          semantic_snapshot_passed: semantic_snapshot_passed,
          accessibility_required: accessibility_required,
          accessibility_passed: accessibility_passed,
          unsafe_construct_rejected: unsafe_construct_rejected,
          repair_attempted: repair_attempted,
          repair_passed: repair_passed,
          failures: failures.freeze
        ).freeze
      end

      def run(source, data_json)
        @runner.call(source: source, data_json: data_json, view_context: @view_context)
      end

      def diagnostic_codes(result)
        result.diagnostics.map { |diagnostic| diagnostic[:code] || diagnostic["code"] }.compact.uniq
      end

      def context_efficiency
        full_bytes = JSON.generate(@catalog.to_h).bytesize
        compact_bytes = @assistant_contract.prompt_context(catalog: @catalog).bytesize
        full_tokens = estimated_tokens(full_bytes)
        compact_tokens = estimated_tokens(compact_bytes)
        omissions = if @catalog.respond_to?(:generation_contract_omissions)
          @catalog.generation_contract_omissions
        else
          [].freeze
        end

        {
          passed: compact_bytes < full_bytes && omissions.empty?,
          executable_constraints_preserved: omissions.empty?,
          omitted_executable_constraints: omissions,
          full_catalog_bytes: full_bytes,
          compact_generation_context_bytes: compact_bytes,
          bytes_saved: full_bytes - compact_bytes,
          byte_reduction_rate: ratio(full_bytes - compact_bytes, full_bytes),
          token_estimate_method: "ceil(bytes/4)",
          full_catalog_estimated_tokens: full_tokens,
          compact_generation_context_estimated_tokens: compact_tokens,
          estimated_tokens_saved: full_tokens - compact_tokens,
          estimated_token_reduction_rate: ratio(full_tokens - compact_tokens, full_tokens)
        }.freeze
      end

      def estimated_tokens(bytes)
        (bytes / 4.0).ceil
      end

      def ratio(numerator, denominator)
        return if denominator.zero?

        (numerator.to_f / denominator).round(4)
      end
    end
  end
end
