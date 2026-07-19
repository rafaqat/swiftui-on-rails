# frozen_string_literal: true

require "test_helper"

module Showcase
  module Playground
    class AssistantContractTest < ActiveSupport::TestCase
      CatalogFixture = Class.new do
        def self.to_h
          {
            "version" => const_get(:VERSION),
            "builders" => {
              "text" => {
                "arguments" => { "positional" => [ { "type" => "text" } ], "keywords" => {} },
                "block" => { "accepted" => false }
              }
            },
            "modifiers" => {
              "text_style" => { "arguments" => [ { "enum" => %w[headline supporting] } ], "tier" => "semantic" }
            }
          }.freeze
        end
      end
      CatalogFixture.const_set(:VERSION, "7.4.2")

      test "embeds the versioned language catalog as the single vocabulary source" do
        contract = AssistantContract.to_h(catalog: CatalogFixture)

        assert_equal AssistantContract::CONTRACT_VERSION, contract.fetch("contract_version")
        assert_equal CatalogFixture::VERSION, contract.dig("language", "version")
        assert_equal CatalogFixture.to_h, contract.fetch("catalog")
        assert_equal "dsl_source_only", contract.dig("response", "content")
        assert_equal 1, contract.dig("response", "root_views")
        assert_includes contract.fetch("objective"), "token_efficiency"
        assert_includes contract.fetch("constraints").map { |entry| entry.fetch("code") }, "catalog_only"
        assert_includes contract.fetch("constraints").map { |entry| entry.fetch("code") }, "stable_identity"
        model_rule = contract.fetch("constraints").find { |entry| entry.fetch("code") == "one_cognitive_model" }

        assert_match(/RenderIR/, model_rule.fetch("rule"))
        assert_match(/Never generate JavaScript/, model_rule.fetch("rule"))
        assert_match(/data-controller/, model_rule.fetch("rule"))
        assert_match(/data-action/, model_rule.fetch("rule"))
        assert_match(/data-\*-target/, model_rule.fetch("rule"))
        assert_match(/event->controller#method/, model_rule.fetch("rule"))
      end

      test "emits deterministic compact JSON prompt context and fingerprint" do
        first = AssistantContract.prompt_context(catalog: CatalogFixture)
        second = AssistantContract.prompt_context(catalog: CatalogFixture)

        assert_equal first, second
        assert_equal AssistantContract.to_h(catalog: CatalogFixture), JSON.parse(first)
        refute_includes first, "\n"
        assert_match(/\A[0-9a-f]{64}\z/, AssistantContract.fingerprint(catalog: CatalogFixture))
        assert_equal AssistantContract.fingerprint(catalog: CatalogFixture), AssistantContract.fingerprint(catalog: CatalogFixture)
      end

      test "deep freezes the contract so prompt inputs cannot drift during a request" do
        contract = AssistantContract.to_h(catalog: CatalogFixture)

        assert contract.frozen?
        assert contract.fetch("language").frozen?
        assert contract.fetch("constraints").frozen?
        assert contract.fetch("constraints").first.frozen?
        assert contract.dig("constraints", 0, "rule").frozen?
      end
    end
  end
end
