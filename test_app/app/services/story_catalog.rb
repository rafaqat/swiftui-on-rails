# frozen_string_literal: true

# Curated presentation metadata for the interactive storybook index.
# StorybookStoryRegistry is the source of truth for which stories exist;
# this catalog is the source of truth for how they are presented — display
# name, category, description, accent gradient, and whether the story's DSL
# source is shown on its page.
#
# Every registered story must either appear here or be listed in
# UNLISTED_STORIES; test/unit/story_catalog_test.rb enforces this so stories
# cannot silently vanish from the index.
class StoryCatalog
  # source_display defaults to true; set it to false for stories whose source
  # is not instructive. source_from: :component displays the backing
  # component's full DSL definition instead of the story method.
  ENTRIES = [
    {
      path: "atlas_mission_control",
      name: "Atlas Mission Control",
      category: "Flagship",
      description: "A complete mission workspace combining navigation, adaptive tools, telemetry, orbital visuals, stable-key planning, alerts, presentations, and document workflows.",
      default_variant: :command_center,
      accent: "from-sky-500 via-blue-600 to-violet-600",
      source_from: :component
    },
    {
      path: "swift_ui_rails_playground",
      name: "SwiftUI Rails Playground",
      category: "Flagship",
      description: "An Xcode-inspired source editor, JSON fixture workspace, sandboxed live canvas, diagnostics, console, and data inspector authored through the component DSL.",
      default_variant: :ide_shell,
      accent: "from-cyan-500 via-blue-600 to-violet-600",
      source_from: :component
    },
    {
      path: "dsl_studio",
      name: "DSL Studio",
      category: "Flagship",
      description: "Twenty-one live controls composing a complete page — navigation, hero, feature grid, and signup form — from DSL primitives alone.",
      default_variant: :default,
      accent: "from-sky-500 to-violet-600"
    },
    {
      path: "dsl_composition",
      name: "Composition Dashboard",
      category: "Flagship",
      description: "Lists, responsive grids, stock states, actions, metrics, and a complete project dashboard composed from the DSL.",
      default_variant: :composition_showcase,
      accent: "from-violet-600 to-fuchsia-500"
    },
    {
      path: "product_layout_simple",
      name: "Product Catalog",
      category: "Flagship",
      description: "Collection rendering, responsive layouts, sorting surfaces, filters, and rich product cards.",
      default_variant: :default,
      accent: "from-amber-500 to-orange-600"
    },
    {
      path: "enhanced_auth",
      name: "Authentication Journey",
      category: "Flagship",
      description: "Login, registration, branded layouts, validation states, and complete-flow compositions.",
      default_variant: :complete_auth_flow,
      accent: "from-rose-500 to-pink-600",
      source_display: false
    },
    {
      path: "swiftui_preview_demo",
      name: "Application Gallery",
      category: "Flagship",
      description: "A landing hero, project form, and team data list built as complete interface sections.",
      default_variant: :hero_section,
      accent: "from-cyan-500 to-blue-600",
      source_display: false
    },
    {
      path: "navigation_presentation",
      name: "Navigation & Presentation",
      category: "Platform",
      description: "Route-first navigation, history-aware tabs, native dialogs and popovers, plus keyboard and overflow-aware toolbars.",
      default_variant: :complete_workflow,
      accent: "from-blue-600 to-cyan-500"
    },
    {
      path: "advanced_content",
      name: "Advanced Content",
      category: "Platform",
      description: "Async images, sanitized rich text, accessible charts, bounded canvas drawing, schematic maps, and sandboxed web content.",
      default_variant: :content_families,
      accent: "from-cyan-500 to-emerald-500"
    },
    {
      path: "wwdc26_workflows",
      name: "Portable WWDC26 Workflows",
      category: "Workflows",
      description: "Accessible reordering, visible swipe actions, signed document provenance, validated imports, and streaming exports.",
      default_variant: :portable_workflows,
      accent: "from-indigo-600 to-violet-500"
    },
    {
      path: "dsl_button",
      name: "DSL Button",
      category: "Components",
      description: "Chainable styling, states, sizing, colors, and interactive property controls.",
      default_variant: :default,
      accent: "from-blue-600 to-indigo-600"
    },
    {
      path: "dsl_card",
      name: "DSL Card",
      category: "Components",
      description: "Composable headers, content, footers, elevation, and interactive card galleries.",
      default_variant: :default,
      accent: "from-emerald-500 to-teal-600"
    },
    {
      path: "dsl_product_card",
      name: "Product Card",
      category: "Components",
      description: "Responsive commerce cards with images, pricing, CTAs, grids, and compact variants.",
      default_variant: :default,
      accent: "from-orange-500 to-red-500"
    },
    {
      path: "button_preview",
      name: "Button Preview Lab",
      category: "Components",
      description: "Nine scenarios covering groups, loading, toggles, icons, floating actions, and confirmation cards.",
      default_variant: :primary_button,
      accent: "from-sky-500 to-cyan-500",
      source_display: false
    },
    {
      path: "preferences",
      name: "Reactive Preferences",
      category: "Reactive",
      description: "Server-owned State, a two-way Binding slider, and signed action round trips restyling a live preview pane.",
      default_variant: :default,
      accent: "from-violet-600 to-fuchsia-700"
    },
    {
      path: "toast",
      name: "Toast Notifications",
      category: "Interactions",
      description: "Auto-dismissing Turbo Stream notifications with hover-pause and a no-JavaScript static fallback.",
      default_variant: :default,
      accent: "from-slate-900 to-slate-700"
    },
    {
      path: "stat_card",
      name: "Stat Card",
      category: "Data Viz",
      description: "Pulse's dashboard tile with headline value, directional delta badge, and detail line.",
      default_variant: :default,
      accent: "from-emerald-500 to-teal-700"
    },
    {
      path: "kanban_card",
      name: "Kanban Card",
      category: "Interactions",
      description: "The Flightplan board's draggable card with priority, tags, and accessible no-JavaScript move controls.",
      default_variant: :default,
      accent: "from-sky-600 to-indigo-700"
    },
    {
      path: "command_palette",
      name: "Atlas Command Palette",
      category: "Interactions",
      description: "A Cmd/Ctrl+K palette that filters server-rendered links with full keyboard navigation through declared RenderIR commands.",
      default_variant: :default,
      accent: "from-slate-800 to-slate-950"
    },
    {
      path: "enhanced_grid",
      name: "Responsive Grid Lab",
      category: "Layout",
      description: "Auto-fit, dense packing, asymmetric gaps, equal-height rows, and responsive product grids.",
      default_variant: :responsive_custom,
      accent: "from-lime-500 to-emerald-600"
    },
    {
      path: "new_dsl_methods",
      name: "Advanced DSL Methods",
      category: "Layout",
      description: "Form controls, rings, gradients, flex behavior, tooltips, and advanced utility composition.",
      default_variant: :form_controls,
      accent: "from-purple-500 to-indigo-600",
      source_display: false
    },
    {
      path: "auth_form",
      name: "Auth Form Builder",
      category: "Patterns",
      description: "Reusable login and registration patterns with validation, branding, and Rails form structure.",
      default_variant: :login,
      accent: "from-pink-500 to-rose-600"
    },
    {
      path: "counter_component",
      name: "Stateful Counter",
      category: "Patterns",
      description: "A focused state-management example with live controls and keyboard-safe actions.",
      default_variant: :default,
      accent: "from-slate-600 to-slate-800",
      source_display: false
    }
  ].freeze

  # Stories that intentionally exist in the registry without appearing on the
  # index. Keep empty unless a story is deliberately internal.
  UNLISTED_STORIES = %w[].freeze

  class << self
    def entries
      ENTRIES
    end

    def fetch(path)
      ENTRIES.find { |entry| entry[:path] == path.to_s }
    end

    def by_category
      ENTRIES.group_by { |entry| entry.fetch(:category) }
    end

    def source_display?(path)
      entry = fetch(path)
      entry ? entry.fetch(:source_display, true) : false
    end

    def source_from_component?(path)
      fetch(path)&.dig(:source_from) == :component
    end
  end
end
