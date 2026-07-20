# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Showcase
  class PlaygroundControllerTest < ActionDispatch::IntegrationTest
    class SequenceGenerator
      attr_reader :requests

      def initialize(*sources)
        @sources = sources
        @requests = []
      end

      def call(**request)
        @requests << request
        @sources.fetch(@requests.length - 1)
      end
    end

    test "renders the server-owned IDE with a native form and isolated preview" do
      get showcase_playground_path

      assert_response :success
      assert_select "#swift-rails-playground[data-playground-mode='server-round-trip']", count: 1
      assert_select "form#playground-run-form[action='#{showcase_playground_run_path}'][method='POST']", count: 1
      assert_select "#playground-source[name='source']", count: 1
      assert_select "#playground-data[name='data_json']", count: 1
      assert_select "#playground-preview[src='#{showcase_playground_preview_path(example: "product-catalog")}'][sandbox='allow-same-origin']", count: 1
      assert_select "#playground-preview[sandbox*='allow-scripts']", count: 0
      assert_select "#playground-diagnostics", count: 1
      assert_select "#playground-run[type='submit'][form='playground-run-form']", count: 1
      assert_select "a[href='#{showcase_playground_language_path}']", minimum: 1
      assert_select "a[href='#{showcase_playground_reliability_path}']", count: 1
      assert_select "[data-controller], [data-action], [data-playground-target]", count: 0
      assert_select "[data-sui-actions], [data-sui-binding]", count: 0
    end

    test "runs edited source through Rails and serves a script-free preview" do
      source = <<~'RUBY'
        vstack(alignment: :leading, spacing: 4) do
          text("Hello #{data[:profile][:name]}").text_style(:headline)
          badge("Server compiled", tone: :success)
        end
      RUBY
      data_json = '{"profile":{"name":"Ada"}}'

      post showcase_playground_run_path,
        params: { example: "product-catalog", source: source, data_json: data_json }

      assert_response :see_other
      redirect_uri = URI.parse(response.location)
      draft_token = Rack::Utils.parse_query(redirect_uri.query).fetch("draft")
      assert_match(/\A[A-Za-z0-9_-]{32}\z/, draft_token)

      follow_redirect!
      assert_response :success
      assert_select "#playground-source", text: /Hello/
      assert_select "#playground-data", text: /Ada/
      assert_select "#playground-diagnostics", text: /No diagnostics/
      assert_select "#playground-preview[src='#{showcase_playground_preview_path(draft: draft_token)}']"

      get showcase_playground_preview_path(draft: draft_token)

      assert_response :success
      assert_equal "no-store", response.headers.fetch("Cache-Control")
      assert_includes response.headers.fetch("Content-Security-Policy"), "default-src 'none'"
      assert_includes response.headers.fetch("Content-Security-Policy"), "form-action 'none'"
      assert_select "#playground-render-root", text: /Hello Ada/
      assert_select "#playground-render-root", text: /Server compiled/
      assert_select "script", count: 0
    end

    test "scopes preview drafts to the Rails session and rejects invalid tokens" do
      get showcase_playground_preview_path(draft: "A" * 32)
      assert_response :not_found

      get showcase_playground_preview_path(draft: "../product-catalog")
      assert_response :not_found
    end

    test "does not persist editor buffers beyond the compiler limits" do
      post showcase_playground_run_path,
        params: {
          example: "product-catalog",
          source: "x" * (Playground::Limits::SOURCE_BYTES + 1),
          data_json: "{}"
        }

      assert_response :unprocessable_content
      assert_select "#playground-preview[src='about:blank']"
      assert_select "#playground-diagnostics", text: /larger|limit|source/i
    end

    test "publishes one cacheable machine-readable language and generation contract" do
      get showcase_playground_language_path, as: :json

      assert_response :success
      assert_equal "application/json", response.media_type
      payload = response.parsed_body
      assert_equal Showcase::Playground::LanguageCatalog::VERSION, payload.dig("catalog", "language_version")
      assert_equal Showcase::Playground::LanguageCatalog::PROFILE, payload.dig("catalog", "profile")
      assert_equal Showcase::Playground::AssistantContract::CONTRACT_VERSION,
        payload.dig("generation_contract", "contract_version")
      assert_equal Showcase::Playground::LanguageCatalog::VERSION,
        payload.dig("generation_contract", "language", "version")
      assert_includes payload.dig("generation_contract", "objective"), "correctness"
      assert_includes payload.dig("generation_contract", "objective"), "token_efficiency"
      assert_equal Showcase::Playground::IntermediateRepresentation::SCHEMA, payload.dig("ir", "schema")
      assert_equal Showcase::Playground::IntermediateRepresentation::VERSION, payload.dig("ir", "version")
      assert_equal Showcase::Playground::AssistantContract.fingerprint, payload.fetch("fingerprint")
      assert_match(/\A[0-9a-f]{64}\z/, payload.fetch("fingerprint"))
      assert response.headers["ETag"].present?
      etag = response.headers.fetch("ETag")

      get showcase_playground_language_path,
        headers: { "HTTP_IF_NONE_MATCH" => etag, "ACCEPT" => "application/json" }

      assert_response :not_modified
      assert_empty response.body
    end

    test "verifies the durable artifact returned by compile and rejects semantic tampering" do
      post showcase_playground_compile_path,
        params: {
          source: 'text("Original").text_style(:headline)',
          data_json: "{}",
          revision: 1
        },
        as: :json

      assert_response :success
      compile_payload = response.parsed_body
      assert compile_payload.fetch("ok")
      artifact = compile_payload.fetch("artifact")
      assert_equal Showcase::Playground::Artifact::SCHEMA, artifact.fetch("schema")
      assert_equal Showcase::Playground::LanguageCatalog::VERSION, artifact.dig("language", "version")
      assert_match(/\A[0-9a-f]{64}\z/, artifact.dig("tests", "semantic_ir_sha256"))

      post showcase_playground_verify_path, params: { artifact: artifact }, as: :json

      assert_response :success
      verification = response.parsed_body
      assert_equal true, verification.fetch("ok")
      assert_equal [], verification.fetch("diagnostics")
      assert_includes verification.fetch("canonical_source"), 'text("Original")'

      tampered = artifact.deep_dup
      tampered["source"] = 'text("Changed").text_style(:headline)'
      post showcase_playground_verify_path, params: { artifact: tampered }, as: :json

      assert_response :unprocessable_content
      rejected = response.parsed_body
      assert_equal false, rejected.fetch("ok")
      assert_equal [ "artifact_semantics" ], rejected.fetch("diagnostics").map { |item| item.fetch("code") }
      refute rejected.key?("canonical_source")
    end

    test "reports assistant unavailability as a bounded service response" do
      with_assistant_generator(nil) do
        post showcase_playground_assist_path,
          params: {
            instruction: "Build a release status",
            source: 'text("Current")',
            data_json: "{}"
          },
          as: :json
      end

      assert_response :service_unavailable
      payload = response.parsed_body
      assert_equal false, payload.fetch("ok")
      assert_equal 0, payload.fetch("attempts")
      assert_equal [ "assistant_unavailable" ], payload.fetch("diagnostics").map { |item| item.fetch("code") }
      refute payload.key?("source")
      refute payload.key?("preview")
      refute_includes response.body, "NoMethodError"
    end

    test "runs an injected assistant through deterministic diagnostic repair" do
      generator = SequenceGenerator.new(
        "vstack do\n  text(\"Incomplete\")\n",
        <<~RUBY
          vstack(alignment: :leading, spacing: 4) do
            text(data[:release][:name]).text_style(:headline)
            badge("Ready", tone: :success, announce: true)
          end
        RUBY
      )

      with_assistant_generator(generator) do
        post showcase_playground_assist_path,
          params: {
            instruction: "Build an accessible release status from the fixture",
            source: 'text("Current draft")',
            data_json: '{"release":{"name":"Atlas"}}'
          },
          as: :json
      end

      assert_response :success
      payload = response.parsed_body
      assert_equal true, payload.fetch("ok")
      assert_equal 2, payload.fetch("attempts")
      assert_includes payload.fetch("source"), "data[:release][:name]"
      assert_includes payload.dig("preview", "html"), "Atlas"
      assert_includes payload.dig("preview", "html"), "Ready"
      assert_equal [], payload.fetch("diagnostics")
      assert_equal Showcase::Playground::Artifact::SCHEMA, payload.dig("preview", "artifact", "schema")

      assert_equal 2, generator.requests.length
      contract = JSON.parse(generator.requests.first.fetch(:messages).first.fetch(:content))
      assert_equal "dsl_source_only", contract.dig("response", "content")
      assert contract.dig("catalog", "builders", "vstack")
      repair = JSON.parse(generator.requests.second.fetch(:messages).last.fetch(:content))
      assert_equal true, repair.fetch("repair")
      assert_equal "syntax", repair.fetch("diagnostics").first.fetch("code")
      assert_match(/complete corrected DSL source/i, repair.fetch("instruction"))
      assert_equal "dsl_source_only", generator.requests.last.dig(:response, :contract)
    end

    test "returns the fixed reliability corpus and correctness metrics" do
      get showcase_playground_reliability_path, as: :json

      assert_response :success
      payload = response.parsed_body
      metrics = payload.fetch("metrics")
      assert_equal true, payload.fetch("ok")
      assert_equal Showcase::Playground::ReliabilityCorpus.all.length, metrics.fetch("total")
      assert_equal metrics.fetch("total"), metrics.fetch("passed")
      assert_equal 1.0, metrics.fetch("expectation_rate")
      assert_equal 1.0, metrics.fetch("semantic_snapshot_accuracy")
      assert_equal 1.0, metrics.fetch("golden_repair_contract_rate")
      assert_nil metrics.fetch("model_first_pass_validity_rate")
      assert_operator metrics.fetch("security_rejections"), :>=, 2
      assert_equal Showcase::Playground::ReliabilityCorpus.all.map(&:id).sort,
        payload.fetch("results").map { |entry| entry.fetch("id") }.sort
      assert payload.fetch("results").all? { |entry| entry.fetch("passed") }
    end

    test "compiles source and returns the client revision in JSON" do
      post showcase_playground_compile_path,
        params: {
          source: 'vstack { text("Live preview") }',
          data_json: "{}",
          revision: 47
        },
        as: :json

      assert_response :success
      assert_equal "application/json", response.media_type

      payload = response.parsed_body
      assert_equal true, payload.fetch("ok")
      assert_equal 47, payload.fetch("revision")
      assert_includes payload.fetch("html"), "Live preview"
      assert_equal [], payload.fetch("diagnostics")
      assert_kind_of Hash, payload.fetch("stats")
      assert_equal({}, payload.fetch("data"))
    end

    test "compiles data-driven conditions without trusting client HTML" do
      post showcase_playground_compile_path,
        params: {
          source: <<~RUBY,
            hstack do
              text(data[:product][:name])
              if data[:product][:in_stock]
                badge("In Stock", tone: :success)
              end
            end
          RUBY
          data_json: {
            product: {
              name: '<img id="owned" src=x onerror=alert(1)>',
              in_stock: true
            }
          }.to_json,
          revision: "fixture-2"
        },
        as: :json

      assert_response :success
      payload = response.parsed_body
      assert payload.fetch("ok")
      assert_equal "fixture-2", payload.fetch("revision")
      assert_includes payload.fetch("html"), "In Stock"
      assert_includes payload.fetch("html"), "&lt;img"
      refute_includes payload.fetch("html"), '<img id="owned"'
    end

    test "returns structured diagnostics for syntax and JSON errors" do
      post showcase_playground_compile_path,
        params: {
          source: "vstack do\n  text(\"Broken\")",
          data_json: "{}",
          revision: 8
        },
        as: :json

      assert_response :success
      syntax_payload = response.parsed_body
      assert_equal false, syntax_payload.fetch("ok")
      assert_equal 8, syntax_payload.fetch("revision")
      assert_kind_of Array, syntax_payload.fetch("diagnostics")
      assert_operator syntax_payload.fetch("diagnostics").length, :>=, 1
      assert_empty syntax_payload.fetch("html").to_s

      post showcase_playground_compile_path,
        params: {
          source: 'text("Fixtures")',
          data_json: "{broken",
          revision: 9
        },
        as: :json

      assert_response :success
      json_payload = response.parsed_body
      assert_equal false, json_payload.fetch("ok")
      assert_equal 9, json_payload.fetch("revision")
      assert_match(/json|fixture|data/i, diagnostic_messages(json_payload).join(" "))
    end

    test "does not accept form-encoded compile requests as an HTML mutation" do
      post showcase_playground_compile_path,
        params: {
          source: 'text("Wrong transport")',
          data_json: "{}",
          revision: 1
        }

      assert_response :not_acceptable
    end

    test "rejects an oversized malformed JSON body before parameter parsing" do
      request_limit = Showcase::Playground::Limits::REQUEST_BYTES
      body = "{\"source\":\"#{"x" * request_limit}"

      post showcase_playground_compile_path,
        params: body,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "CONTENT_LENGTH" => body.bytesize.to_s
        }

      assert_response :content_too_large
      assert_equal "application/json", response.media_type
      payload = response.parsed_body
      assert_equal false, payload.fetch("ok")
      assert_equal 0, payload.fetch("revision")
      assert_equal "", payload.fetch("html")
      assert_equal [ "request_size" ], payload.fetch("diagnostics").map { |diagnostic| diagnostic.fetch("code") }
      assert_operator response.body.bytesize, :<, 4.kilobytes
      refute_includes response.body, "x" * 1.kilobyte
    end

    test "returns a bounded generic response for an under-limit malformed JSON envelope" do
      body = '{"source":"unterminated'
      compiler_called = false
      unexpected_compile = lambda do |**|
        compiler_called = true
        raise "compiler must not receive a malformed request envelope"
      end

      Showcase::Playground::Runner.stub(:call, unexpected_compile) do
        post showcase_playground_compile_path,
          params: body,
          headers: {
            "CONTENT_TYPE" => "application/json",
            "CONTENT_LENGTH" => body.bytesize.to_s
          }
      end

      assert_response :bad_request
      assert_equal "application/json", response.media_type
      payload = response.parsed_body
      assert_equal false, payload.fetch("ok")
      assert_equal 0, payload.fetch("revision")
      assert_equal "", payload.fetch("html")
      assert_equal [ "request_syntax" ], payload.fetch("diagnostics").map { |diagnostic| diagnostic.fetch("code") }
      assert_equal({}, payload.fetch("stats"))
      assert_equal({}, payload.fetch("data"))
      assert_not compiler_called
      assert_operator response.body.bytesize, :<, 4.kilobytes
      refute_includes response.body, "JSON::ParserError"
      refute_includes response.body, "ActionDispatch::Http::Parameters"
      refute_includes response.body, "unexpected token at"
      refute_includes response.body, Rails.root.to_s
      refute_match(/backtrace/i, response.body)
    end

    test "compile failures expose a generic diagnostic rather than exception details" do
      failure = ->(**) { raise StandardError, "postgres://admin:secret@internal.example/private" }

      Showcase::Playground::Runner.stub(:call, failure) do
        post showcase_playground_compile_path,
          params: {
            source: 'text("Hello")',
            data_json: "{}",
            revision: 11
          },
          as: :json
      end

      assert_response :internal_server_error
      assert_equal "application/json", response.media_type
      refute_includes response.body, "postgres"
      refute_includes response.body, "admin:secret"
      refute_includes response.body, "internal.example"
      refute_includes response.body, Rails.root.to_s
      assert_equal false, response.parsed_body.fetch("ok")
      assert_equal 11, response.parsed_body.fetch("revision")
      assert_operator response.parsed_body.fetch("diagnostics").length, :>=, 1
    end

    private

    def with_assistant_generator(generator)
      options = Rails.application.config.x
      previous_group = options.swift_ui_playground
      group = previous_group || ActiveSupport::OrderedOptions.new
      previous_generator = group.generator
      options.swift_ui_playground = group
      group.generator = generator
      yield
    ensure
      if previous_group
        group.generator = previous_generator
      else
        options.swift_ui_playground = nil
      end
    end

    def diagnostic_messages(payload)
      payload.fetch("diagnostics").map { |diagnostic| diagnostic.fetch("message", "") }
    end
  end
end
