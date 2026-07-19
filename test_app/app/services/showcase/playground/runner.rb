# frozen_string_literal: true

module Showcase
  module Playground
    class Runner
      def self.call(source:, data_json:, view_context:)
        new(source: source, data_json: data_json, view_context: view_context).call
      end

      def initialize(source:, data_json:, view_context:)
        @source = source.to_s
        @data_json = data_json.to_s
        @view_context = view_context
      end

      def call
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        compilation = SourceCompiler.call(@source)
        if compilation.diagnostics.any?
          return failed_result(
            compilation.diagnostics,
            started_at,
            data: {},
            ast_nodes: compilation.node_count
          )
        end

        fixture = FixtureParser.call(@data_json)
        return failed_result(fixture.diagnostics, started_at, data: fixture.data, data_values: fixture.value_count, ast_nodes: compilation.node_count) if fixture.diagnostics.any?

        validation = SemanticValidator.call(compilation.program)
        unless validation.success?
          return failed_result(
            validation.diagnostics,
            started_at,
            data: fixture.data,
            data_values: fixture.value_count,
            ast_nodes: compilation.node_count,
            ir_version: IntermediateRepresentation::VERSION,
            language_version: LanguageCatalog::VERSION
          )
        end

        rendering = Renderer.call(program: validation.document, data: fixture.data, view_context: @view_context)
        formatting = SourceFormatter.call(@source)
        Result.new(
          html: rendering.html,
          diagnostics: rendering.diagnostics,
          data: fixture.data,
          canonical_source: formatting.success? ? formatting.source : nil,
          ir: validation.document,
          render_ir: rendering.render_ir,
          stats: stats(
            started_at,
            data_values: fixture.value_count,
            ast_nodes: compilation.node_count,
            views: rendering.view_count,
            iterations: rendering.iteration_count,
            operations: rendering.operation_count,
            html_bytes: rendering.html.bytesize,
            render_ir_nodes: rendering.render_ir&.each_node&.count || 0,
            render_ir_bytes: rendering.render_ir&.canonical_json&.bytesize || 0,
            render_ir_version: rendering.render_ir&.version,
            ir_version: IntermediateRepresentation::VERSION,
            language_version: LanguageCatalog::VERSION
          )
        )
      rescue StandardError => error
        Rails.logger.error("[Playground] Unexpected runner failure: #{error.class}: #{error.message}")
        Rails.logger.error(error.backtrace.first(12).join("\n")) if error.backtrace
        failed_result(
          [ {
            source: "view",
            severity: "error",
            code: "runner_failure",
            message: "The preview could not be rendered safely.",
            line: 1,
            column: 1,
            end_line: 1,
            end_column: 1,
            path: nil
          } ],
          started_at || Process.clock_gettime(Process::CLOCK_MONOTONIC),
          data: {}
        )
      end

      private

      def failed_result(diagnostics, started_at, data:, **values)
        Result.new(html: "", diagnostics: diagnostics, data: data, stats: stats(started_at, **values))
      end

      def stats(started_at, **values)
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
        {
          render_ms: elapsed.round(1),
          source_lines: source_line_count,
          source_bytes: @source.bytesize,
          data_bytes: @data_json.bytesize,
          data_values: 0,
          ast_nodes: 0,
          views: 0,
          iterations: 0,
          operations: 0,
          html_bytes: 0,
          render_ir_nodes: 0,
          render_ir_bytes: 0,
          render_ir_version: SwiftUIRails::RenderIR::VERSION,
          ir_version: IntermediateRepresentation::VERSION,
          language_version: LanguageCatalog::VERSION
        }.merge(values)
      end

      def source_line_count
        return 0 if @source.bytesize > Limits::SOURCE_BYTES
        return 0 if @source.empty?

        @source.count("\n") + 1
      end
    end
  end
end
