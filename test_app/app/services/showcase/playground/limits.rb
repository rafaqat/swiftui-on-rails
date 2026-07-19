# frozen_string_literal: true

module Showcase
  module Playground
    module Limits
      CATALOG_LIMITS = LanguageCatalog.to_h.fetch("limits")

      SOURCE_BYTES = CATALOG_LIMITS.fetch("source_bytes")
      SOURCE_LINES = CATALOG_LIMITS.fetch("source_lines")
      SOURCE_LINE_BYTES = CATALOG_LIMITS.fetch("source_line_bytes")
      DATA_BYTES = CATALOG_LIMITS.fetch("data_bytes")
      DATA_DEPTH = CATALOG_LIMITS.fetch("data_depth")
      DATA_VALUES = CATALOG_LIMITS.fetch("data_values")
      DATA_KEYS_PER_OBJECT = CATALOG_LIMITS.fetch("data_keys_per_object")
      DATA_KEY_BYTES = CATALOG_LIMITS.fetch("data_key_bytes")
      DATA_ARRAY_LENGTH = CATALOG_LIMITS.fetch("data_array_length")
      DATA_STRING_BYTES = CATALOG_LIMITS.fetch("data_string_bytes")
      REQUEST_BYTES = CATALOG_LIMITS.fetch("request_bytes")
      AST_NODES = CATALOG_LIMITS.fetch("ast_nodes")
      AST_DEPTH = CATALOG_LIMITS.fetch("ast_depth")
      MODIFIERS_PER_VIEW = CATALOG_LIMITS.fetch("modifiers_per_view")
      RENDERED_VIEWS = CATALOG_LIMITS.fetch("rendered_views")
      LOOP_ITERATIONS = CATALOG_LIMITS.fetch("loop_iterations")
      TOTAL_LOOP_ITERATIONS = CATALOG_LIMITS.fetch("total_loop_iterations")
      EVALUATOR_OPERATIONS = CATALOG_LIMITS.fetch("evaluator_operations")
      RENDERED_TEXT_BYTES = CATALOG_LIMITS.fetch("rendered_text_bytes")
      HTML_BYTES = CATALOG_LIMITS.fetch("html_bytes")
      DIAGNOSTICS = CATALOG_LIMITS.fetch("diagnostics")
    end
  end
end
