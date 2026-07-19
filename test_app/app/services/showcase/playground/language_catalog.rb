# frozen_string_literal: true

module Showcase
  module Playground
    # The machine-readable contract for source submitted to the browser
    # playground. Keep this document JSON-native: it is consumed by the editor,
    # documentation, validators, and LLM authoring tools as well as Ruby code.
    #
    # SourceCompiler, SemanticValidator, Renderer, the editor, formatter, and
    # assistant contract all consume this document so vocabulary drift is a
    # failing compatibility condition rather than an implicit convention.
    class LanguageCatalog
      VERSION = "1.1.0"
      INITIAL_VERSION = "1.0.0"
      SCHEMA_VERSION = 1
      PROFILE = "browser_playground"

      CONTAINER_BUILDERS = %w[vstack hstack zstack grid section article].freeze
      VIEW_CONTEXTS = %w[root container_block conditional_branch collection_body].freeze
      VIEW_PARENTS = ([ "$root" ] + CONTAINER_BUILDERS + %w[if unless for_each]).freeze
      NESTED_CONTEXTS = VIEW_CONTEXTS.reject { |context| context == "root" }.freeze
      NESTED_PARENTS = VIEW_PARENTS.reject { |parent| parent == "$root" }.freeze

      STABLE_AVAILABILITY = {
        "since" => INITIAL_VERSION,
        "status" => "stable",
        "profiles" => [ PROFILE ]
      }.freeze

      COLOR_NAMES = %w[
        white black red blue green yellow gray purple pink orange indigo slate
        zinc neutral stone amber teal cyan sky violet fuchsia rose transparent
        current inherit
      ].freeze
      BASE_COLOR_NAMES = %w[white black transparent current inherit].freeze
      SHADEABLE_COLOR_NAMES = COLOR_NAMES.reject do |name|
        BASE_COLOR_NAMES.include?(name)
      end.freeze
      COLOR_SHADES = %w[50 100 200 300 400 500 600 700 800 900 950].freeze
      SPACING_VALUES = %w[
        0 px 0.5 1 1.5 2 2.5 3 3.5 4 5 6 7 8 9 10 11 12 14 16 20 24
        28 32 36 40 44 48 52 56 60 64 72 80 96
      ].freeze
      SIZE_VALUES = (SPACING_VALUES + %w[auto full 1/2 1/3 2/3 1/4 2/4 3/4 screen min max fit]).uniq.freeze

      TYPES = {
        "expression" => {
          "kind" => "expression",
          "description" => "Any expression supported by the playground expression grammar."
        },
        "condition" => {
          "kind" => "expression",
          "description" => "An expression using Ruby truthiness; only false and nil are false."
        },
        "scalar_text" => {
          "kind" => "scalar",
          "values" => %w[string integer float boolean nil symbol],
          "description" => "Escaped text; arrays and objects are rejected."
        },
        "boolean" => {
          "kind" => "primitive",
          "values" => [ true, false ]
        },
        "number" => {
          "kind" => "number",
          "finite" => true,
          "maximum_magnitude" => 1_000_000_000_000
        },
        "integer" => {
          "kind" => "integer",
          "maximum_magnitude" => 1_000_000_000_000
        },
        "identifier_key" => {
          "kind" => "string",
          "pattern" => "^[a-zA-Z_][a-zA-Z0-9_-]{0,63}$",
          "max_bytes" => 64
        },
        "stack_alignment" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[leading center trailing top bottom]
        },
        "alignment" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[
            leading center trailing top bottom top_leading top_trailing
            bottom_leading bottom_trailing
          ]
        },
        "badge_tone" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[neutral info success warning danger]
        },
        "button_style" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[
            automatic bordered_prominent primary bordered secondary borderless
            ghost plain danger
          ]
        },
        "button_size" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[mini xs small sm regular md large lg extra_large xl]
        },
        "icon_name" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[
            search star x check plus minus chevron_left chevron_right chevron_up
            chevron_down arrow_left arrow_right arrow_up arrow_down heart circle
            square warning info gear menu sun moon play pause refresh mail pencil
            trash clock bolt dot ellipsis
          ]
        },
        "foreground_style" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[
            primary secondary tertiary quaternary accent success warning danger
            on_accent
          ]
        },
        "background_style" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[canvas surface elevated muted accent success warning danger]
        },
        "font" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[
            large_title title title2 title3 headline subheadline body callout
            footnote caption caption2
          ]
        },
        "text_style" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[title headline body supporting metadata caption]
        },
        "safe_color" => {
          "kind" => "patterned_enum",
          "input_forms" => %w[string symbol],
          "forms" => [
            { "template" => "{name}", "name_values" => BASE_COLOR_NAMES },
            {
              "template" => "{name}-{shade}",
              "name_values" => SHADEABLE_COLOR_NAMES,
              "shade_values" => COLOR_SHADES
            }
          ]
        },
        "spacing" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol integer float],
          "values" => SPACING_VALUES
        },
        "size" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol integer float],
          "values" => SIZE_VALUES
        },
        "max_size" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol integer float],
          "values" => SIZE_VALUES.reject { |value| value == "auto" }
        },
        "text_size" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[xs sm base lg xl 2xl 3xl 4xl 5xl 6xl 7xl 8xl 9xl]
        },
        "font_weight" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[thin extralight light normal medium semibold bold extrabold black]
        },
        "corner_radius" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[none sm md lg xl 2xl 3xl full]
        },
        "shadow" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol],
          "values" => %w[none sm md lg xl 2xl inner]
        },
        "border_width" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol integer],
          "values" => %w[0 2 4 8]
        },
        "opacity" => {
          "kind" => "enum",
          "input_forms" => %w[string symbol integer],
          "values" => %w[0 5 10 20 25 30 40 50 60 70 75 80 90 95 100]
        }
      }.freeze

      BUILDERS = {
        "vstack" => {
          "kind" => "builder",
          "summary" => "Arrange child views vertically.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "alignment" => { "type" => "stack_alignment", "required" => false, "default" => "center" },
              "spacing" => { "type" => "number", "required" => false, "default" => 8, "minimum" => 0, "maximum" => 64 }
            }
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Alignment is allowlisted and spacing is bounded from 0 through 64." ]
        },
        "hstack" => {
          "kind" => "builder",
          "summary" => "Arrange child views horizontally.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "alignment" => { "type" => "stack_alignment", "required" => false, "default" => "center" },
              "spacing" => { "type" => "number", "required" => false, "default" => 8, "minimum" => 0, "maximum" => 64 }
            }
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Alignment is allowlisted and spacing is bounded from 0 through 64." ]
        },
        "zstack" => {
          "kind" => "builder",
          "summary" => "Overlay child views.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "alignment" => { "type" => "alignment", "required" => false, "default" => "center" }
            }
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Alignment is selected from a fixed enum." ]
        },
        "grid" => {
          "kind" => "builder",
          "summary" => "Arrange child views in a bounded column grid.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "columns" => { "type" => "integer", "required" => false, "default" => 2, "minimum" => 1, "maximum" => 6 },
              "spacing" => { "type" => "integer", "required" => false, "default" => 8, "minimum" => 0, "maximum" => 32 }
            }
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Columns and spacing are bounded integers." ]
        },
        "section" => {
          "kind" => "builder",
          "summary" => "Group related content in a semantic section.",
          "arguments" => { "positional" => [], "keywords" => {} },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => []
        },
        "article" => {
          "kind" => "builder",
          "summary" => "Group self-contained content in a semantic article.",
          "arguments" => { "positional" => [], "keywords" => {} },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => []
        },
        "text" => {
          "kind" => "builder",
          "summary" => "Render escaped scalar text.",
          "arguments" => {
            "positional" => [ { "name" => "content", "type" => "scalar_text", "required" => true } ],
            "keywords" => {}
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Content is escaped and collections are rejected." ]
        },
        "button" => {
          "kind" => "builder",
          "summary" => "Render a non-submitting preview button.",
          "arguments" => {
            "positional" => [ { "name" => "label", "type" => "scalar_text", "required" => true, "non_empty" => true } ],
            "keywords" => {
              "disabled" => { "type" => "boolean", "required" => false, "default" => false }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [
            "Visible labels must provide a non-empty accessible name.",
            "Buttons are visual preview controls and cannot dispatch browser or server actions."
          ]
        },
        "badge" => {
          "kind" => "builder",
          "summary" => "Render a status label using a semantic tone.",
          "arguments" => {
            "positional" => [ { "name" => "label", "type" => "scalar_text", "required" => true } ],
            "keywords" => {
              "tone" => { "type" => "badge_tone", "required" => false, "default" => "neutral" },
              "announce" => { "type" => "boolean", "required" => false, "default" => false }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Tone is selected from a fixed semantic enum." ]
        },
        "icon" => {
          "kind" => "builder",
          "summary" => "Render a glyph from the framework icon allowlist.",
          "arguments" => {
            "positional" => [ { "name" => "name", "type" => "icon_name", "required" => true } ],
            "keywords" => {
              "size" => { "type" => "integer", "required" => false, "default" => 16, "minimum" => 8, "maximum" => 64 }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Names are allowlisted and size is a bounded integer." ]
        },
        "spacer" => {
          "kind" => "builder",
          "summary" => "Insert flexible space with an optional minimum length.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "min_length" => { "type" => "number", "required" => false, "default" => nil, "minimum" => 0, "maximum" => 256 }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Minimum length is bounded from 0 through 256." ]
        },
        "divider" => {
          "kind" => "builder",
          "summary" => "Render a visual separator.",
          "arguments" => { "positional" => [], "keywords" => {} },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => []
        },
        "progress_view" => {
          "kind" => "builder",
          "summary" => "Render determinate or indeterminate progress.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "value" => { "type" => "number", "required" => false, "default" => nil, "minimum" => 0, "maximum" => 1_000_000 },
              "total" => { "type" => "number", "required" => false, "default" => 1.0, "minimum_exclusive" => 0, "maximum" => 1_000_000 },
              "label" => { "type" => "scalar_text", "required" => false, "default" => "Progress", "non_empty" => true }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Numeric values are finite and bounded." ]
        },
        "gauge" => {
          "kind" => "builder",
          "summary" => "Render a bounded value from zero through one hundred.",
          "arguments" => {
            "positional" => [],
            "keywords" => {
              "value" => { "type" => "number", "required" => true, "minimum" => 0, "maximum" => 100 },
              "label" => { "type" => "scalar_text", "required" => false, "default" => "Value", "non_empty" => true }
            }
          },
          "block" => { "mode" => "forbidden" },
          "contexts" => VIEW_CONTEXTS,
          "legal_parents" => VIEW_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Value is required, finite, and bounded from 0 through 100." ]
        }
      }.freeze

      def self.modifier_entry(
        type:,
        summary:,
        tier:,
        arity: 1,
        default: :__none__,
        legal_targets: [ "*" ],
        recommended_targets: nil,
        security: []
      )
        minimum, maximum = arity.is_a?(Range) ? [ arity.begin, arity.end ] : [ arity, arity ]
        argument = { "name" => "value", "type" => type, "required" => minimum.positive? }
        argument["default"] = default unless default == :__none__

        {
          "kind" => "modifier",
          "summary" => summary,
          "arguments" => {
            "positional" => maximum.zero? ? [] : [ argument ],
            "arity" => { "minimum" => minimum, "maximum" => maximum },
            "keywords" => {}
          },
          "legal_targets" => legal_targets,
          "recommended_targets" => recommended_targets || legal_targets,
          "contexts" => [ "modifier_chain" ],
          "tier" => tier,
          "availability" => STABLE_AVAILABILITY,
          "security" => security
        }
      end
      private_class_method :modifier_entry

      MODIFIERS = {
        "p" => modifier_entry(type: "spacing", summary: "Set padding on all edges using a spacing token.", tier: "escape_hatch"),
        "px" => modifier_entry(type: "spacing", summary: "Set horizontal padding using a spacing token.", tier: "escape_hatch"),
        "py" => modifier_entry(type: "spacing", summary: "Set vertical padding using a spacing token.", tier: "escape_hatch"),
        "pt" => modifier_entry(type: "spacing", summary: "Set top padding using a spacing token.", tier: "escape_hatch"),
        "pr" => modifier_entry(type: "spacing", summary: "Set right padding using a spacing token.", tier: "escape_hatch"),
        "pb" => modifier_entry(type: "spacing", summary: "Set bottom padding using a spacing token.", tier: "escape_hatch"),
        "pl" => modifier_entry(type: "spacing", summary: "Set left padding using a spacing token.", tier: "escape_hatch"),
        "m" => modifier_entry(type: "spacing", summary: "Set margin on all edges using a spacing token.", tier: "escape_hatch"),
        "mx" => modifier_entry(type: "spacing", summary: "Set horizontal margin using a spacing token.", tier: "escape_hatch"),
        "my" => modifier_entry(type: "spacing", summary: "Set vertical margin using a spacing token.", tier: "escape_hatch"),
        "mt" => modifier_entry(type: "spacing", summary: "Set top margin using a spacing token.", tier: "escape_hatch"),
        "mr" => modifier_entry(type: "spacing", summary: "Set right margin using a spacing token.", tier: "escape_hatch"),
        "mb" => modifier_entry(type: "spacing", summary: "Set bottom margin using a spacing token.", tier: "escape_hatch"),
        "ml" => modifier_entry(type: "spacing", summary: "Set left margin using a spacing token.", tier: "escape_hatch"),
        "padding" => modifier_entry(type: "spacing", summary: "Set view padding using a framework spacing token.", tier: "semantic"),
        "bg" => modifier_entry(
          type: "safe_color",
          summary: "Set a presentation color directly.",
          tier: "escape_hatch",
          security: [ "Only allowlisted color names and shades are accepted; prefer background_style." ]
        ),
        "text_color" => modifier_entry(
          type: "safe_color",
          summary: "Set a text color directly.",
          tier: "escape_hatch",
          recommended_targets: %w[text button badge icon],
          security: [ "Only allowlisted color names and shades are accepted; prefer foreground_style." ]
        ),
        "text_size" => modifier_entry(
          type: "text_size",
          summary: "Set a low-level text size token.",
          tier: "escape_hatch",
          recommended_targets: %w[text button badge],
          security: [ "Size is allowlisted; prefer font or text_style." ]
        ),
        "font_weight" => modifier_entry(
          type: "font_weight",
          summary: "Set a low-level font weight token.",
          tier: "escape_hatch",
          recommended_targets: %w[text button badge],
          security: [ "Weight is allowlisted; prefer font or text_style." ]
        ),
        "foreground_style" => modifier_entry(
          type: "foreground_style",
          summary: "Apply a theme-owned semantic foreground role.",
          tier: "semantic",
          recommended_targets: %w[text button badge icon]
        ),
        "background_style" => modifier_entry(
          type: "background_style",
          summary: "Apply a theme-owned semantic background role.",
          tier: "semantic"
        ),
        "font" => modifier_entry(
          type: "font",
          summary: "Apply a semantic typography role.",
          tier: "semantic",
          recommended_targets: %w[text button badge]
        ),
        "text_style" => modifier_entry(
          type: "text_style",
          summary: "Apply a coordinated semantic font and foreground preset.",
          tier: "semantic",
          recommended_targets: %w[text button badge]
        ),
        "rounded" => modifier_entry(type: "corner_radius", summary: "Set a low-level corner-radius token.", tier: "escape_hatch", arity: 0..1, default: "framework_default"),
        "shadow" => modifier_entry(type: "shadow", summary: "Set a low-level shadow token.", tier: "escape_hatch", arity: 0..1, default: "framework_default"),
        "border" => modifier_entry(type: "border_width", summary: "Set a low-level border width.", tier: "escape_hatch", arity: 0..1, default: "framework_default"),
        "border_color" => modifier_entry(
          type: "safe_color",
          summary: "Set a low-level border color.",
          tier: "escape_hatch",
          security: [ "Only allowlisted color names and shades are accepted." ]
        ),
        "opacity" => modifier_entry(type: "opacity", summary: "Set an allowlisted opacity percentage.", tier: "escape_hatch"),
        "w" => modifier_entry(type: "size", summary: "Set a low-level width token.", tier: "escape_hatch"),
        "h" => modifier_entry(type: "size", summary: "Set a low-level height token.", tier: "escape_hatch"),
        "min_w" => modifier_entry(type: "size", summary: "Set a low-level minimum-width token.", tier: "escape_hatch"),
        "min_h" => modifier_entry(type: "size", summary: "Set a low-level minimum-height token.", tier: "escape_hatch"),
        "max_w" => modifier_entry(type: "max_size", summary: "Set a low-level maximum-width token.", tier: "escape_hatch"),
        "max_h" => modifier_entry(type: "max_size", summary: "Set a low-level maximum-height token.", tier: "escape_hatch"),
        "hidden" => modifier_entry(type: "boolean", summary: "Remove a view from visual and accessibility layout.", tier: "semantic", arity: 0..1, default: true),
        "disabled" => modifier_entry(type: "boolean", summary: "Set whether a button is disabled.", tier: "semantic", arity: 0..1, default: true, legal_targets: [ "button" ]),
        "button_style" => modifier_entry(type: "button_style", summary: "Apply a semantic button treatment.", tier: "semantic", legal_targets: [ "button" ]),
        "button_size" => modifier_entry(type: "button_size", summary: "Apply a semantic button control size.", tier: "semantic", legal_targets: [ "button" ]),
        "w_full" => modifier_entry(type: "size", summary: "Expand to the full available width.", tier: "escape_hatch", arity: 0)
      }.freeze

      STATEMENTS = {
        "for_each" => {
          "kind" => "control_flow",
          "summary" => "Render a body once for each object in a bounded fixture-data array.",
          "arguments" => {
            "positional" => [ { "name" => "collection", "type" => "expression", "required" => true, "runtime_type" => "array<object>" } ],
            "keywords" => {
              "id" => { "type" => "identifier_key", "required" => true }
            }
          },
          "block" => { "mode" => "required", "parameters" => 1, "content" => "statements" },
          "contexts" => NESTED_CONTEXTS,
          "legal_parents" => NESTED_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [
            "Collection length and total iterations are bounded.",
            "Items must be objects with unique string or integer stable identifiers."
          ]
        },
        "if" => {
          "kind" => "control_flow",
          "summary" => "Render one of two branches using Ruby truthiness.",
          "arguments" => {
            "syntax" => [ { "name" => "predicate", "type" => "condition", "required" => true } ]
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements", "else" => "optional" },
          "contexts" => NESTED_CONTEXTS,
          "legal_parents" => NESTED_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Only the allowlisted expression grammar can be used as a predicate." ]
        },
        "unless" => {
          "kind" => "control_flow",
          "summary" => "Render one of two branches using an inverted predicate.",
          "arguments" => {
            "syntax" => [ { "name" => "predicate", "type" => "condition", "required" => true } ]
          },
          "block" => { "mode" => "required", "parameters" => 0, "content" => "statements", "else" => "optional" },
          "contexts" => NESTED_CONTEXTS,
          "legal_parents" => NESTED_PARENTS,
          "tier" => "semantic",
          "availability" => STABLE_AVAILABILITY,
          "security" => [ "Only the allowlisted expression grammar can be used as a predicate." ]
        }
      }.freeze

      EXPRESSIONS = {
        "literal" => {
          "forms" => %w[string interpolated_string symbol integer float true false nil],
          "security" => [ "Numeric literals must be finite and bounded." ]
        },
        "symbol" => {
          "syntax" => ":name",
          "security" => [ "Symbols are inert enum-like values; constant lookup is unavailable." ]
        },
        "variable" => {
          "root" => [ "data" ],
          "loop_variables" => "one lexical variable declared by for_each"
        },
        "index" => {
          "syntax" => "receiver[key]",
          "receivers" => %w[object array],
          "security" => [ "Object keys must exist; array indexes must be in bounds." ]
        },
        "interpolation" => {
          "syntax" => '#{expression}',
          "security" => [ "Interpolated values are converted to escaped scalar text." ]
        },
        "boolean" => { "operators" => %w[&& ||] },
        "not" => { "operators" => [ "!" ] },
        "binary" => {
          "operators" => %w[== != < <= > >= + - * /],
          "security" => [ "Ordered comparison types are checked; arithmetic operands and results must be finite and bounded; division by zero is rejected." ]
        },
        "operation" => {
          "operators" => %w[count length size empty? first last],
          "arguments" => 0,
          "security" => [ "Operations are read-only and receiver types are checked." ]
        }
      }.freeze

      DOCUMENT = {
        "name" => "swift_ui_rails_playground",
        "language_version" => VERSION,
        "catalog_schema_version" => SCHEMA_VERSION,
        "profile" => PROFILE,
        "source_kind" => "untrusted_ruby_shaped_dsl",
        "application_model" => {
          "authority" => "ruby_render_ir",
          "state" => "server_owned",
          "behavior" => "catalogued_dsl_declarations",
          "browser_runtime" => "framework_owned_allowlisted_protocol_interpreter",
          "application_javascript" => false,
          "stimulus" => false,
          "controller_dispatch" => false,
          "arbitrary_browser_commands" => false,
          "forbidden_dom_contracts" => [
            "data-controller",
            "data-action",
            "data-*-target",
            "event->controller#method"
          ],
          "forbidden_authoring_surfaces" => [
            "javascript_source",
            "stimulus_controller",
            "stimulus_action",
            "stimulus_target",
            "stimulus_param",
            "inline_event_handler",
            "dom_query",
            "dom_mutation"
          ]
        },
        "execution" => {
          "eval" => false,
          "pipeline" => %w[parse compile validate render],
          "root" => { "kind" => "view", "minimum" => 1, "maximum" => 1 }
        },
        "limits" => {
          "source_bytes" => 32 * 1024,
          "source_lines" => 500,
          "source_line_bytes" => 2 * 1024,
          "data_bytes" => 64 * 1024,
          "data_depth" => 16,
          "data_values" => 2_000,
          "data_keys_per_object" => 100,
          "data_key_bytes" => 128,
          "data_array_length" => 200,
          "data_string_bytes" => 8 * 1024,
          "request_bytes" => 256 * 1024,
          "ast_nodes" => 2_000,
          "ast_depth" => 24,
          "modifiers_per_view" => 16,
          "rendered_views" => 500,
          "loop_iterations" => 100,
          "total_loop_iterations" => 250,
          "evaluator_operations" => 20_000,
          "rendered_text_bytes" => 192 * 1024,
          "html_bytes" => 256 * 1024,
          "diagnostics" => 20
        },
        "tiers" => {
          "semantic" => "Preferred, theme-owned intent suitable for generated DSL.",
          "escape_hatch" => "Supported low-level presentation token; omit from constrained generation unless necessary."
        },
        "types" => TYPES,
        "builders" => BUILDERS,
        "modifiers" => MODIFIERS,
        "statements" => STATEMENTS,
        "expressions" => EXPRESSIONS,
        "security" => [
          "Submitted source is parsed with Prism and never evaluated as Ruby.",
          "Only catalogued views, modifiers, control flow, and expressions are accepted.",
          "Fixture data is JSON and all rendered text is escaped.",
          "Resource budgets bound parsing, evaluation, looping, text, and output.",
          "Application behavior is declared in the DSL and represented in RenderIR; submitted source cannot define JavaScript, Stimulus controllers, DOM selectors, or event-handler attributes."
        ]
      }.freeze

      class << self
        def to_h
          DOCUMENT
        end

        def types
          TYPES
        end

        def builders
          BUILDERS
        end

        def modifiers
          MODIFIERS
        end

        def statements
          STATEMENTS
        end

        def expressions
          EXPRESSIONS
        end

        def builder(name)
          BUILDERS[name.to_s]
        end

        def modifier(name)
          MODIFIERS[name.to_s]
        end

        def fetch(section, name = nil)
          collection = DOCUMENT.fetch(section.to_s)
          name.nil? ? collection : collection.fetch(name.to_s)
        end

        # Compact, generation-oriented contract. It intentionally omits prose,
        # low-level presentation escape hatches, defaults that the runtime can
        # supply, and documentation-only metadata. The full catalogue remains
        # available through +to_h+ for editors and documentation.
        def for_generation(include_escape_hatches: false)
          cache = include_escape_hatches ? :@generation_catalog_with_escape_hatches : :@semantic_generation_catalog
          cached = instance_variable_get(cache)
          return cached if cached

          tiers = include_escape_hatches ? %w[semantic escape_hatch] : [ "semantic" ]
          selected_modifiers = MODIFIERS.select { |_name, entry| tiers.include?(entry.fetch("tier")) }
          referenced_types = generation_type_names(selected_modifiers)

          instance_variable_set(cache, deep_freeze({
            "language_version" => VERSION,
            "profile" => PROFILE,
            "root" => "exactly_one_view",
            "application_model" => DOCUMENT.fetch("application_model"),
            "builders" => BUILDERS.transform_values { |entry| compact_entry(entry) },
            "modifiers" => selected_modifiers.transform_values { |entry| compact_entry(entry) },
            "statements" => STATEMENTS.transform_values { |entry| compact_entry(entry) },
            "expressions" => EXPRESSIONS.transform_values { |entry| compact_expression(entry) },
            "types" => TYPES.slice(*referenced_types).transform_values { |entry| compact_type(entry) }
          }))
        end

        # Returns executable catalogue paths lost by the compact model context.
        # Prose, availability metadata, defaults, and block-content descriptions
        # are intentionally omitted; constraints that affect validity are not.
        def generation_contract_omissions(include_escape_hatches: false)
          compact = for_generation(include_escape_hatches: include_escape_hatches)
          tiers = include_escape_hatches ? %w[semantic escape_hatch] : [ "semantic" ]
          omissions = []

          {
            "builders" => BUILDERS,
            "modifiers" => MODIFIERS.select { |_name, entry| tiers.include?(entry.fetch("tier")) },
            "statements" => STATEMENTS
          }.each do |section, entries|
            entries.each do |name, entry|
              generated = compact.fetch(section).fetch(name)
              compare_generation_subset(
                strip_generation_metadata(entry.fetch("arguments", {}), ignored: [ "default" ]),
                generated.fetch("args"),
                "$.#{section}.#{name}.args",
                omissions
              )
              compare_generation_subset(
                strip_generation_metadata(entry.fetch("block", {}), ignored: [ "content" ]),
                generated.fetch("block"),
                "$.#{section}.#{name}.block",
                omissions
              )
              omissions << "$.#{section}.#{name}.parents" if entry["legal_parents"] && generated["parents"] != entry["legal_parents"]
              omissions << "$.#{section}.#{name}.targets" if entry["legal_targets"] && generated["targets"] != entry["legal_targets"]
              omissions << "$.#{section}.#{name}.tier" if generated["tier"] != entry["tier"]
            end
          end

          compact.fetch("types").each_key do |name|
            compare_generation_subset(
              TYPES.fetch(name).except("description"),
              compact.fetch("types").fetch(name),
              "$.types.#{name}",
              omissions
            )
          end
          EXPRESSIONS.each do |name, entry|
            compare_generation_subset(
              entry.except("security"),
              compact.fetch("expressions").fetch(name),
              "$.expressions.#{name}",
              omissions
            )
          end
          omissions.freeze
        end

        # Every Tailwind utility that can be produced from a finite catalogue
        # value. The compiled stylesheet test treats this list as a release
        # contract, preventing accepted modifiers from becoming visual no-ops.
        def tailwind_utility_classes
          @tailwind_utility_classes ||= begin
            classes = []
            classes.concat(prefixed_values(%w[p px py pt pr pb pl m mx my mt mr mb ml], type_values("spacing")))
            classes.concat(prefixed_values(%w[w h min-w min-h], type_values("size")))
            classes.concat(prefixed_values(%w[max-w max-h], type_values("max_size")))
            classes.concat(prefixed_values(%w[text bg border], safe_color_values))
            classes.concat(prefixed_values([ "text" ], type_values("text_size")))
            classes.concat(prefixed_values([ "font" ], type_values("font_weight")))
            classes.concat(prefixed_values([ "rounded" ], type_values("corner_radius")))
            classes.concat(prefixed_values([ "shadow" ], type_values("shadow")))
            classes.concat(prefixed_values([ "border" ], type_values("border_width")))
            classes.concat(prefixed_values([ "opacity" ], type_values("opacity")))
            classes.concat((0..BUILDERS.dig("grid", "arguments", "keywords", "spacing", "maximum")).map { |value| "gap-#{value}" })
            classes.concat(%w[border rounded shadow w-full])
            deep_freeze(classes.uniq.sort)
          end
        end

        private

        def type_values(name)
          TYPES.fetch(name).fetch("values")
        end

        def safe_color_values
          TYPES.fetch("safe_color").fetch("forms").flat_map do |form|
            names = form.fetch("name_values")
            shades = form["shade_values"]
            shades ? names.product(shades).map { |name, shade| "#{name}-#{shade}" } : names
          end
        end

        def prefixed_values(prefixes, values)
          prefixes.product(values).map { |prefix, value| "#{prefix}-#{value}" }
        end

        def generation_type_names(selected_modifiers)
          entries = BUILDERS.values + selected_modifiers.values + STATEMENTS.values
          entries.flat_map do |entry|
            arguments = entry.fetch("arguments", {})
            arguments.fetch("positional", []).filter_map { |argument| argument["type"] } +
              arguments.fetch("keywords", {}).values.filter_map { |argument| argument["type"] } +
              arguments.fetch("syntax", []).filter_map { |argument| argument["type"] }
          end.uniq.sort
        end

        def compact_entry(entry)
          result = {
            "args" => compact_arguments(entry.fetch("arguments", {})),
            "block" => entry.fetch("block", {}).except("content"),
            "tier" => entry["tier"]
          }
          result["parents"] = entry["legal_parents"] if entry["legal_parents"]
          result["targets"] = entry["legal_targets"] if entry["legal_targets"]
          result.compact
        end

        def compact_arguments(arguments)
          result = {}
          positional = arguments.fetch("positional", [])
          result["positional"] = positional.map { |argument| compact_argument(argument) } if positional.any?
          keywords = arguments.fetch("keywords", {})
          result["keywords"] = keywords.transform_values { |argument| compact_argument(argument) } if keywords.any?
          syntax = arguments.fetch("syntax", [])
          result["syntax"] = syntax.map { |argument| compact_argument(argument) } if syntax.any?
          result["arity"] = arguments["arity"] if arguments["arity"]
          result
        end

        def compact_argument(argument)
          argument.except("default")
        end

        def compact_expression(entry)
          entry.except("security")
        end

        def compact_type(entry)
          entry.except("description")
        end

        def strip_generation_metadata(value, ignored:)
          case value
          when Hash
            value.each_with_object({}) do |(key, child), output|
              output[key] = strip_generation_metadata(child, ignored: ignored) unless ignored.include?(key)
            end
          when Array
            value.map { |child| strip_generation_metadata(child, ignored: ignored) }
          else
            value
          end
        end

        def compare_generation_subset(expected, actual, path, omissions)
          case expected
          when Hash
            unless actual.is_a?(Hash)
              omissions << path
              return
            end
            expected.each do |key, value|
              if actual.key?(key)
                compare_generation_subset(value, actual[key], "#{path}.#{key}", omissions)
              elsif value.respond_to?(:empty?) && value.empty?
                next
              else
                omissions << "#{path}.#{key}"
              end
            end
          when Array
            unless actual.is_a?(Array) && actual.length == expected.length
              omissions << path
              return
            end
            expected.each_with_index do |value, index|
              compare_generation_subset(value, actual[index], "#{path}[#{index}]", omissions)
            end
          else
            omissions << path unless actual == expected
          end
        end
      end

      def self.deep_freeze(value)
        case value
        when Hash
          value.each do |key, child|
            key.freeze
            deep_freeze(child)
          end
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end
      private_class_method :deep_freeze

      deep_freeze(DOCUMENT)
    end
  end
end
