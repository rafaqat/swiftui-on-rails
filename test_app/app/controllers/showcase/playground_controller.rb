# frozen_string_literal: true

require "securerandom"

module Showcase
  class PlaygroundController < ApplicationController
    DRAFT_TOKEN = /\A[A-Za-z0-9_-]{32}\z/
    DRAFT_TTL = 30.minutes
    FALLBACK_DRAFT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)

    before_action :reject_oversized_json_request, only: %i[compile assist verify]
    before_action :reject_oversized_form_request, only: :run

    def show
      draft_token = normalized_draft_token(params[:draft])
      draft = load_draft(draft_token) if draft_token
      assign_playground(draft: draft, draft_token: (draft_token if draft))
    end

    # The browser submits the two editor buffers as a normal HTML form. Rails
    # remains the sole owner of compilation, diagnostics, IR lowering, and the
    # next rendered document.
    def run
      source = params[:source].to_s
      data_json = params[:data_json].to_s
      selected_example = Playground::Examples.find(params[:example])
      result = Playground::Runner.call(source: source, data_json: data_json, view_context: view_context)

      unless storable_draft?(source, data_json)
        return assign_and_render_unstored_draft(
          selected_example: selected_example,
          source: source,
          data_json: data_json,
          result: result
        )
      end

      draft_token = SecureRandom.urlsafe_base64(24)
      draft_store.write(
        draft_cache_key(draft_token),
        {
          "example" => selected_example.id,
          "source" => source.dup.freeze,
          "data_json" => data_json.dup.freeze
        }.freeze,
        expires_in: DRAFT_TTL,
        compress: true
      )

      redirect_to showcase_playground_path(draft: draft_token), status: :see_other
    end

    # The iframe never receives srcdoc or executable source. It performs a
    # same-origin GET, repeats the safe compiler pipeline on the server, and
    # receives a script-free document under a restrictive CSP.
    def preview
      source, data_json = preview_input
      return head :not_found unless source && data_json

      @preview_result = Playground::Runner.call(
        source: source,
        data_json: data_json,
        view_context: view_context
      )
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["X-Frame-Options"] = "SAMEORIGIN"
      response.headers["Content-Security-Policy"] = preview_content_security_policy
      render layout: "playground_preview"
    end

    def compile
      revision = 0
      unless request.media_type == "application/json"
        return render json: { error: "Playground compile requests must use JSON." }, status: :not_acceptable
      end

      revision = normalized_revision(params[:revision])
      source = params[:source].to_s
      data_json = params[:data_json].to_s
      result = Playground::Runner.call(source: source, data_json: data_json, view_context: view_context)

      render json: result.as_json.merge(revision: revision)
    rescue ActionDispatch::Http::Parameters::ParseError
      render_compile_error(
        code: "request_syntax",
        message: "The compile request is not valid JSON.",
        revision: 0,
        status: :bad_request
      )
    rescue StandardError => error
      Rails.logger.error("[Playground] Compile endpoint failure: #{error.class}: #{error.message}")
      render_compile_error(
        code: "request_failure",
        message: "The preview request could not be completed safely.",
        revision: revision || 0,
        status: :internal_server_error
      )
    end

    def language
      contract = Playground::AssistantContract.to_h
      fingerprint = Playground::AssistantContract.fingerprint
      fresh_when(etag: fingerprint, public: false)
      return if performed?

      render json: {
        catalog: Playground::LanguageCatalog.to_h,
        generation_contract: contract,
        fingerprint: fingerprint,
        ir: {
          schema: Playground::IntermediateRepresentation::SCHEMA,
          version: Playground::IntermediateRepresentation::VERSION
        }
      }
    end

    def assist
      return render_json_transport_error unless request.media_type == "application/json"

      session = Playground::AssistantSession.call(
        instruction: params[:instruction],
        data_json: params[:data_json],
        current_source: params[:source],
        view_context: view_context,
        generator: assistant_generator
      )
      render json: session.as_json, status: session.success? ? :ok : assistant_status(session)
    rescue ActionDispatch::Http::Parameters::ParseError
      render_tool_error(code: "request_syntax", message: "The assistant request is not valid JSON.", status: :bad_request)
    end

    def verify
      return render_json_transport_error unless request.media_type == "application/json"

      artifact = params[:artifact]
      artifact = artifact.to_unsafe_h if artifact.respond_to?(:to_unsafe_h)
      verification = Playground::ArtifactVerifier.call(artifact, view_context: view_context)
      render json: verification.as_json, status: verification.success? ? :ok : :unprocessable_content
    rescue ActionDispatch::Http::Parameters::ParseError
      render_tool_error(code: "request_syntax", message: "The artifact request is not valid JSON.", status: :bad_request)
    end

    def reliability
      report = Playground::ReliabilityEvaluator.call(view_context: view_context)
      render json: report.as_json, status: report.success? ? :ok : :unprocessable_content
    end

    def token_benchmark
      report = TokenBenchmark::Evaluator.call
      render json: report.as_json, status: report.success? ? :ok : :unprocessable_content
    rescue TokenBenchmark::Corpus::Invalid => error
      Rails.logger.error("[Playground] Token benchmark corpus is invalid: #{error.message}")
      render json: {
        ok: false,
        error: "The fixed token benchmark corpus is invalid."
      }, status: :unprocessable_content
    end

    private

    def assign_playground(draft: nil, draft_token: nil)
      @examples = Playground::Examples.all
      @selected_example = Playground::Examples.find(draft&.fetch("example", nil) || params[:example])
      @source = draft&.fetch("source", nil) || @selected_example.source
      @data_json = draft&.fetch("data_json", nil) || @selected_example.data_json
      @assistant_available = assistant_generator.respond_to?(:call)
      @initial_result = Playground::Runner.call(
        source: @source,
        data_json: @data_json,
        view_context: view_context
      )
      @preview_url = if draft_token
        showcase_playground_preview_path(draft: draft_token)
      else
        showcase_playground_preview_path(example: @selected_example.id)
      end
    end

    def assign_and_render_unstored_draft(selected_example:, source:, data_json:, result:)
      @examples = Playground::Examples.all
      @selected_example = selected_example
      @source = source
      @data_json = data_json
      @assistant_available = assistant_generator.respond_to?(:call)
      @initial_result = result
      @preview_url = nil
      render :show, status: :unprocessable_content
    end

    def preview_input
      if params[:draft].present?
        token = normalized_draft_token(params[:draft])
        draft = load_draft(token) if token
        return unless draft

        return [ draft.fetch("source"), draft.fetch("data_json") ]
      end

      example = Playground::Examples.find(params[:example])
      [ example.source, example.data_json ]
    end

    def normalized_draft_token(value)
      token = value.to_s
      token if token.match?(DRAFT_TOKEN)
    end

    def load_draft(token)
      return unless token

      value = draft_store.read(draft_cache_key(token))
      return unless value.is_a?(Hash)
      return unless value["source"].is_a?(String) && value["data_json"].is_a?(String)
      return unless storable_draft?(value["source"], value["data_json"])

      value
    end

    def storable_draft?(source, data_json)
      source.bytesize <= Playground::Limits::SOURCE_BYTES &&
        data_json.bytesize <= Playground::Limits::DATA_BYTES
    end

    def draft_cache_key(token)
      "showcase/playground/drafts/#{playground_session_scope}/#{token}"
    end

    def playground_session_scope
      session[:showcase_playground_scope] ||= SecureRandom.hex(16)
    end

    def draft_store
      Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? FALLBACK_DRAFT_STORE : Rails.cache
    end

    def preview_content_security_policy
      "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; " \
        "font-src 'self' data:; frame-ancestors 'self'; base-uri 'none'; form-action 'none'"
    end

    # content_length.to_i treats an absent Content-Length as 0, so a chunked
    # request could stream an arbitrarily large body past the cap. Reject a
    # missing or malformed length as well as an oversized one (fail closed).
    def request_body_too_large_or_unknown?
      header = request.get_header("CONTENT_LENGTH")
      return true if header.blank?

      length = Integer(header, exception: false)
      length.nil? || length > Playground::Limits::REQUEST_BYTES
    end

    def reject_oversized_form_request
      return unless request_body_too_large_or_unknown?

      render plain: "The playground form is too large.", status: :content_too_large
    end

    def reject_oversized_json_request
      return unless request_body_too_large_or_unknown?

      message = "The playground request is larger than #{Playground::Limits::REQUEST_BYTES / 1024} KiB."
      if action_name == "compile"
        render_compile_error(code: "request_size", message: message, revision: 0, status: 413)
      else
        render_tool_error(code: "request_size", message: message, status: 413)
      end
    end

    def assistant_generator
      Rails.application.config.x.swift_ui_playground&.generator
    end

    def assistant_status(session)
      code = session.diagnostics.first&.fetch(:code, nil).to_s
      code == "assistant_unavailable" ? :service_unavailable : :unprocessable_content
    end

    def render_json_transport_error
      render_tool_error(
        code: "request_transport",
        message: "Playground tool requests must use JSON.",
        status: :not_acceptable
      )
    end

    def render_tool_error(code:, message:, status:)
      render json: {
        ok: false,
        diagnostics: [ {
          source: "request",
          severity: "error",
          code: code,
          message: message,
          line: 1,
          column: 1,
          end_line: 1,
          end_column: 1,
          path: nil
        } ]
      }, status: status
    end

    def render_compile_error(code:, message:, revision:, status:)
      render json: {
        ok: false,
        revision: revision,
        html: "",
        diagnostics: [ {
          source: "view",
          severity: "error",
          code: code,
          message: message,
          line: 1,
          column: 1,
          end_line: 1,
          end_column: 1,
          path: nil
        } ],
        stats: {},
        data: {}
      }, status: status
    end

    def normalized_revision(value)
      revision = Integer(value, exception: false)
      return revision.clamp(0, 2_147_483_647) if revision

      token = value.to_s
      token.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) ? token : 0
    end
  end
end
