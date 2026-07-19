# frozen_string_literal: true

module Showcase
  module TokenBenchmark
    # Measures a validated corpus. A successful report means the paired source
    # was valid and countable, not that a model generated it or parity ran.
    class Evaluator
      SIDES = %w[react_rails swift_ui_rails].freeze
      SCOPES = %i[view_source authored_production_closure].freeze

      Report = Struct.new(:methodology, :summary, :comparisons, keyword_init: true) do
        def success?
          true
        end

        def as_json(*)
          {
            ok: success?,
            methodology: methodology,
            summary: summary,
            comparisons: comparisons
          }
        end
      end

      class << self
        def call(corpus: Corpus.default, counter: Counter.new)
          new(corpus: corpus, counter: counter).call
        end
      end

      def initialize(corpus:, counter:)
        @corpus = corpus
        @counter = counter
      end

      def call
        comparisons = @corpus.cases.map { |benchmark| compare(benchmark) }.freeze
        Report.new(
          methodology: methodology,
          summary: summarize(comparisons),
          comparisons: comparisons
        ).freeze
      end

      private

      def compare(benchmark)
        sides = SIDES.to_h do |side|
          implementation = benchmark.fetch("implementations").fetch(side)
          view_files = implementation.fetch("view_source")
          production_files = view_files + implementation.fetch("production_support")
          [
            side.to_sym,
            {
              view_source: @counter.call(view_files).as_json.freeze,
              authored_production_closure: @counter.call(production_files).as_json.freeze
            }.freeze
          ]
        end

        {
          id: benchmark.fetch("id"),
          label: benchmark.fetch("label"),
          contract: benchmark.fetch("contract"),
          parity: {
            status: "swift_component_render_gate_react_declared_not_executed",
            swift_ui_rails: "byte_matched_executable_application_component",
            react_rails: "source_closure_validated_runtime_not_executed",
            checks: benchmark.fetch("parity_checks")
          }.freeze,
          react_rails: sides.fetch(:react_rails),
          swift_ui_rails: sides.fetch(:swift_ui_rails),
          savings: savings_for(sides)
        }.freeze
      end

      def methodology
        source = @corpus.methodology
        {
          corpus_version: @corpus.corpus_version,
          corpus_sha256: @corpus.source_digest,
          measurement_scope: "paired_reference_source_tokens",
          track: source.fetch("track"),
          comparison_unit: source.fetch("comparison_unit"),
          baseline: "react_rails",
          candidate: "swift_ui_rails",
          tokenizer: @counter.metadata,
          scopes: source.fetch("scopes"),
          shared_inputs: source.fetch("shared_inputs"),
          exclusions: source.fetch("exclusions"),
          parity_gate_execution: "swift_component_render_gate_in_test_suite_react_runtime_not_executed",
          provider_model_execution: "not_run",
          claim_boundary: source.fetch("claim_boundary")
        }.freeze
      end

      def summarize(comparisons)
        sides = SIDES.to_h do |side|
          scopes = SCOPES.to_h do |scope|
            counts = comparisons.map { |comparison| comparison.fetch(side.to_sym).fetch(scope) }
            [ scope, sum_counts(counts) ]
          end
          [ side.to_sym, scopes.freeze ]
        end

        {
          case_count: comparisons.length,
          aggregation: "micro_sum",
          react_rails: sides.fetch(:react_rails),
          swift_ui_rails: sides.fetch(:swift_ui_rails),
          savings: savings_for(sides),
          macro: macro_summary(comparisons)
        }.freeze
      end

      def macro_summary(comparisons)
        SCOPES.to_h do |scope|
          rates = comparisons.map { |comparison| comparison.fetch(:savings).fetch(scope).fetch(:token_rate) }.compact
          sorted = rates.sort
          [
            scope,
            {
              case_count: rates.length,
              mean_token_rate: rates.any? ? (rates.sum / rates.length).round(4) : nil,
              median_token_rate: median(sorted),
              positive_savings_cases: rates.count(&:positive?),
              negative_savings_cases: rates.count(&:negative?),
              tied_cases: rates.count(&:zero?)
            }.freeze
          ]
        end.freeze
      end

      def median(sorted)
        return if sorted.empty?

        middle = sorted.length / 2
        return sorted.fetch(middle) if sorted.length.odd?

        ((sorted.fetch(middle - 1) + sorted.fetch(middle)) / 2.0).round(4)
      end

      def sum_counts(counts)
        %i[bytes characters lines tokens files].to_h do |metric|
          [ metric, counts.sum { |count| count.fetch(metric) } ]
        end.freeze
      end

      def savings_for(sides)
        SCOPES.to_h do |scope|
          baseline = sides.fetch(:react_rails).fetch(scope)
          candidate = sides.fetch(:swift_ui_rails).fetch(scope)
          byte_savings = baseline.fetch(:bytes) - candidate.fetch(:bytes)
          token_savings = baseline.fetch(:tokens) - candidate.fetch(:tokens)
          [
            scope,
            {
              bytes: byte_savings,
              tokens: token_savings,
              byte_rate: ratio(byte_savings, baseline.fetch(:bytes)),
              token_rate: ratio(token_savings, baseline.fetch(:tokens))
            }.freeze
          ]
        end.freeze
      end

      def ratio(numerator, denominator)
        return if denominator.zero?

        (numerator.to_f / denominator).round(4)
      end
    end
  end
end
