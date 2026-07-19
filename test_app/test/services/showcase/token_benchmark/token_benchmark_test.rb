# frozen_string_literal: true

require "test_helper"
require "json"
require "tempfile"
require "yaml"

module Showcase
  module TokenBenchmark
    class TokenBenchmarkTest < ActiveSupport::TestCase
      test "loads a strict deeply frozen paired corpus with executable source closures" do
        corpus = Corpus.default

        assert_equal 3, corpus.cases.length
        assert_equal "idiomatic_react_vs_swift_ui_framework_leverage", corpus.methodology.fetch("track")
        assert corpus.cases.frozen?
        assert corpus.cases.all?(&:frozen?)
        assert corpus.cases.all? { |entry| entry.fetch("shared_fixture").keys.all?(String) }

        corpus.cases.each do |entry|
          swift_file = entry.dig("implementations", "swift_ui_rails", "view_source").sole
          assert_equal Rails.root.join(swift_file.fetch("path")).binread, swift_file.fetch("content")

          react_support = entry.dig("implementations", "react_rails", "production_support")
          assert react_support.any? { |file| file.fetch("path").end_with?("_entry.jsx") }
          assert react_support.any? { |file| file.fetch("path").end_with?(".css") }
          assert react_support.any? { |file| file.fetch("path") == "package.json" }
          assert react_support.any? { |file| file.fetch("path") == "Gemfile.react_rails" }
        end

        assert_raises(FrozenError) { corpus.cases.first.fetch("contract") << "mutate" }
      end

      test "rejects schema drift unsafe paths noncanonical source and incomplete React closure" do
        unknown_key = corpus_document
        unknown_key["unexpected"] = true
        assert_raises(Corpus::Invalid) { Corpus.new(unknown_key) }

        unsafe_path = corpus_document
        unsafe_path.dig("cases", 0, "implementations", "react_rails", "view_source", 0)["path"] = "../escape.jsx"
        error = assert_raises(Corpus::Invalid) { Corpus.new(unsafe_path) }
        assert_match(/relative source path/, error.message)

        trailing_whitespace = corpus_document
        react_source = trailing_whitespace.dig("cases", 0, "implementations", "react_rails", "view_source", 0)
        react_source["content"] = react_source.fetch("content").sub("\n", "  \n")
        error = assert_raises(Corpus::Invalid) { Corpus.new(trailing_whitespace) }
        assert_match(/trailing whitespace/, error.message)

        incomplete_closure = corpus_document
        package = incomplete_closure.dig("cases", 0, "implementations", "react_rails", "production_support")
          .find { |file| file.fetch("path") == "package.json" }
        package["content"] = package.fetch("content").gsub(" --jsx=automatic", "")
        error = assert_raises(Corpus::Invalid) { Corpus.new(incomplete_closure) }
        assert_match(/automatic JSX transform/, error.message)
      end

      test "rejects duplicate fixture keys before YAML can silently replace them" do
        Tempfile.create([ "token-benchmark", ".yml" ]) do |file|
          file.write("schema_version: 1.0.0\nschema_version: 2.0.0\n")
          file.flush

          error = assert_raises(Corpus::Invalid) { Corpus.load(file.path) }
          assert_match(/duplicate benchmark key "schema_version"/, error.message)
        end
      end

      test "counts exact o200k tokens after neutral source normalization" do
        counter = Counter.new
        count = counter.call([ { "path" => "example.txt", "content" => "hello world\r\n" } ])

        assert_equal 12, count.bytes
        assert_equal 12, count.characters
        assert_equal 1, count.lines
        assert_equal 3, count.tokens
        assert_equal 1, count.files
        assert_equal "tiktoken_bpe", counter.metadata.fetch(:method)
        assert_equal "o200k_base", counter.metadata.fetch(:encoding)
        assert_equal "0.0.16", counter.metadata.fetch(:implementation_version)
        assert counter.metadata.fetch(:exact)
        assert_not counter.metadata.fetch(:provider_api_usage)
      end

      test "renders every counted Swift component directly from the shared string-key fixture" do
        cases = Corpus.default.cases.index_by { |entry| entry.fetch("id") }

        service_data = cases.fetch("service-status").fetch("shared_fixture")
        service = render_component(TokenBenchmarks::ServiceStatusComponent.new(service: service_data.fetch("service")))
        assert_css service, '[role="heading"][aria-level="2"]', text: "Payments", count: 1
        assert_css service, '[role="status"]', text: "Operational", count: 1

        catalog_data = cases.fetch("product-catalog").fetch("shared_fixture")
        catalog = render_component(
          TokenBenchmarks::ProductCatalogComponent.new(
            store: catalog_data.fetch("store"),
            products: catalog_data.fetch("products")
          )
        )
        assert_css catalog, '[role="heading"][aria-level="1"]', text: "Northstar Supply", count: 1
        assert_css catalog, '[role="heading"][aria-level="2"]', count: 2
        assert_css catalog, "#product-compass", count: 1
        assert_css catalog, "#product-lamp", count: 1
        assert_css catalog, "button", text: "Inspect", count: 2
        assert_css catalog, 'span[class~="bg-green-50"]', text: "In Stock", count: 1
        assert_css catalog, 'span[class~="bg-red-50"]', text: "Sold Out", count: 1

        mission_data = cases.fetch("mission-readiness").fetch("shared_fixture")
        mission = render_component(
          TokenBenchmarks::MissionReadinessComponent.new(
            mission: mission_data.fetch("mission"),
            systems: mission_data.fetch("systems")
          )
        )
        assert_css mission, '[role="heading"][aria-level="1"]', text: "Artemis Relay", count: 1
        assert_css mission, '[role="heading"][aria-level="2"]', count: 3
        assert_css mission, "#system-guidance", count: 1
        assert_css mission, "#system-telemetry", count: 1
        assert_css mission, "#system-recovery", count: 1
        assert_css mission, 'progress[aria-label="Mission progress"]', count: 1
        assert_css mission, 'meter[aria-label="Readiness"]', count: 1
        assert_css mission, "button", text: "Run diagnostic", count: 1
      end

      test "reports exact signed micro totals and equal-case macro statistics" do
        report = Evaluator.call
        payload = report.as_json

        assert report.success?
        assert_equal %i[ok methodology summary comparisons], payload.keys
        assert_equal 3, payload.dig(:summary, :case_count)
        assert_equal "micro_sum", payload.dig(:summary, :aggregation)
        assert_equal "paired_reference_source_tokens", payload.dig(:methodology, :measurement_scope)
        assert_equal "not_run", payload.dig(:methodology, :provider_model_execution)
        assert_equal "swift_component_render_gate_in_test_suite_react_runtime_not_executed",
          payload.dig(:methodology, :parity_gate_execution)

        %i[view_source authored_production_closure].each do |scope|
          react_tokens = payload.fetch(:comparisons).sum { |comparison| comparison.dig(:react_rails, scope, :tokens) }
          swift_tokens = payload.fetch(:comparisons).sum { |comparison| comparison.dig(:swift_ui_rails, scope, :tokens) }
          assert_equal react_tokens, payload.dig(:summary, :react_rails, scope, :tokens)
          assert_equal swift_tokens, payload.dig(:summary, :swift_ui_rails, scope, :tokens)
          assert_equal react_tokens - swift_tokens, payload.dig(:summary, :savings, scope, :tokens)

          rates = payload.fetch(:comparisons).map { |comparison| comparison.dig(:savings, scope, :token_rate) }.sort
          assert_equal (rates.sum / rates.length).round(4), payload.dig(:summary, :macro, scope, :mean_token_rate)
          assert_equal rates.fetch(1), payload.dig(:summary, :macro, scope, :median_token_rate)
        end

        assert payload.fetch(:comparisons).frozen?
        assert_raises(FrozenError) { payload.fetch(:comparisons).first.fetch(:savings)[:new] = true }
        round_trip = JSON.parse(JSON.generate(payload))
        assert_equal true, round_trip.fetch("ok")
        assert_equal 3, round_trip.fetch("comparisons").length
      end

      test "success and savings preserve an unfavorable Swift result" do
        counter = Class.new do
          def metadata
            { method: "test", encoding: "test", exact: true }.freeze
          end

          def call(files)
            swift = files.any? { |file| file.fetch("path").include?("token_benchmarks") }
            tokens = files.length * (swift ? 100 : 10)
            Counter::Count.new(
              bytes: tokens,
              characters: tokens,
              lines: files.length,
              tokens: tokens,
              files: files.length
            ).freeze
          end
        end.new

        report = Evaluator.call(counter: counter)

        assert report.success?
        assert_operator report.summary.dig(:savings, :view_source, :tokens), :<, 0
        assert_operator report.summary.dig(:savings, :authored_production_closure, :tokens), :<, 0
        assert_equal 3, report.summary.dig(:macro, :view_source, :negative_savings_cases)
      end

      private

      def corpus_document
        YAML.safe_load_file(Corpus::DEFAULT_PATH, permitted_classes: [], permitted_symbols: [], aliases: false)
      end

      def render_component(component)
        Nokogiri::HTML.fragment(ApplicationController.render(component, layout: false))
      end

      def assert_css(fragment, selector, count:, text: nil)
        nodes = fragment.css(selector)
        assert_equal count, nodes.length, "Expected #{count} matches for #{selector}, got #{nodes.length}"
        return unless text

        assert nodes.all? { |node| node.text.strip == text }, "Expected every #{selector} to contain #{text.inspect}"
      end
    end
  end
end
