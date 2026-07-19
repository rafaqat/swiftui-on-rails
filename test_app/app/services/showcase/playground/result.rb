# frozen_string_literal: true

module Showcase
  module Playground
    class Result
      attr_reader :html, :diagnostics, :stats, :data, :canonical_source, :ir, :render_ir, :artifact

      def initialize(html:, diagnostics:, stats:, data:, canonical_source: nil, ir: nil, render_ir: nil, artifact: nil)
        @html = html.to_s.dup.freeze
        @diagnostics = IntermediateRepresentation::Normalizer.call(
          Array(diagnostics).first(Limits::DIAGNOSTICS).map(&:deep_stringify_keys),
          path: "$.diagnostics"
        )
        @stats = IntermediateRepresentation::Normalizer.call(stats.deep_stringify_keys, path: "$.stats")
        @data = IntermediateRepresentation::Normalizer.call(data, path: "$.data")
        @canonical_source = canonical_source&.to_s&.freeze
        @ir = ir
        @render_ir = validate_render_ir(render_ir)
        @artifact = artifact || build_artifact
        freeze
      end

      def success?
        diagnostics.none? { |diagnostic| diagnostic.fetch("severity", "error") == "error" }
      end

      def as_json(*)
        {
          ok: success?,
          html: html,
          diagnostics: diagnostics,
          stats: stats,
          data: data,
          canonical_source: canonical_source,
          authoring_ir: ir&.to_h,
          render_ir: render_ir&.to_h,
          artifact: artifact&.to_h
        }
      end

      private

      def validate_render_ir(value)
        return if value.nil?
        return value if value.is_a?(SwiftUIRails::RenderIR::Document)

        raise TypeError, "render_ir must be a SwiftUIRails::RenderIR::Document"
      end

      def build_artifact
        return unless canonical_source && ir && diagnostics.none? { |diagnostic| diagnostic.fetch("severity", "error") == "error" }

        Artifact.build(source: canonical_source, data: data, ir: ir)
      end
    end
  end
end
