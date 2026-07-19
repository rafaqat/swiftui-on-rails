# frozen_string_literal: true

# Curated registry of every interactive demo application. The /demos gallery,
# the home page, and per-demo chrome all render from this catalog, and
# test/unit/demo_catalog_test.rb guards that every entry stays routable.
#
# Each demo declares exactly one primary interaction model so the gallery can
# teach which Rails-first tool answers which problem:
#   :url      — every interaction is a GET/POST that changes the URL; Turbo
#               morphing smooths the update. Works with JavaScript disabled.
#   :turbo    — server-owned state mutated by form posts and re-rendered
#               through Turbo Streams.
#   :cable    — realtime pushes over Action Cable broadcast into the page.
#   :reactive — Ruby state and interaction declarations lowered to RenderIR;
#               the gem runtime applies allowlisted commands and keyed patches.
class DemoCatalog
  INTERACTION_MODELS = {
    url: "URL-driven",
    turbo: "Turbo Streams",
    cable: "Action Cable",
    reactive: "RenderIR Reactive"
  }.freeze

  ENTRIES = [
    {
      slug: "playground",
      name: "SwiftUI Rails Playground",
      category: "Showcase",
      description: "An Xcode-inspired live workspace for safe DSL editing, JSON fixtures, responsive previews, and structured diagnostics.",
      model: :reactive,
      route: :showcase_playground_path,
      accent: "from-cyan-500 via-blue-600 to-violet-600"
    },
    {
      slug: "ledger",
      name: "Ledger",
      category: "Data",
      description: "Sort, filter, search, and paginate 500 invoices with zero custom state JavaScript — every interaction is a URL, morphed smoothly by Turbo.",
      model: :url,
      route: :demos_ledger_path,
      accent: "from-slate-700 to-slate-950",
      source_component: "Demos::LedgerComponent"
    },
    {
      slug: "motion",
      name: "Motion",
      category: "Motion",
      description: "Six animations with zero animation libraries: insertion/removal transitions, spring-pressed buttons, staggered reveals, view-transition shuffles, and pure-CSS ambience.",
      model: :turbo,
      route: :demos_motion_path,
      accent: "from-orange-500 via-rose-500 to-violet-600",
      source_component: "Demos::MotionComponent"
    },
    {
      slug: "relay",
      name: "Relay",
      category: "Communication",
      description: "A split-pane inbox with j/k/e keyboard triage, swipe-to-archive, URL-addressed threads, and Turbo Stream sends that always earn a reply.",
      model: :turbo,
      route: :demos_relay_path,
      accent: "from-blue-600 to-indigo-800",
      source_component: "Demos::RelayComponent"
    },
    {
      slug: "dispatch",
      name: "Dispatch",
      category: "Data",
      description: "A declarative pan/zoom interaction over the DSL's schematic map with URL-driven station selection — interactive viz without application JavaScript or a mapping library.",
      model: :reactive,
      route: :demos_dispatch_path,
      accent: "from-teal-600 to-emerald-800",
      source_component: "Demos::DispatchComponent"
    },
    {
      slug: "onboard",
      name: "Onboard",
      category: "Forms",
      description: "A four-step wizard where the URL addresses each step, the server validates every advance, and the back button just works — zero custom JavaScript.",
      model: :url,
      route: :demos_onboard_path,
      accent: "from-cyan-600 to-sky-800",
      source_component: "Demos::OnboardComponent"
    },
    {
      slug: "preferences",
      name: "Preferences",
      category: "Reactive",
      description: "A settings panel where server-owned State and browser-editable Bindings restyle a live preview through signed action round trips — no bespoke JavaScript.",
      model: :reactive,
      route: :demos_preferences_path,
      accent: "from-violet-600 to-fuchsia-700",
      story: "preferences",
      source_component: "PreferencesComponent"
    },
    {
      slug: "aperture",
      name: "Aperture",
      category: "Media",
      description: "A masonry photo gallery with lazy async images and a keyboard-navigable native-dialog lightbox that deep-links from the URL.",
      model: :url,
      route: :demos_aperture_path,
      accent: "from-fuchsia-600 to-violet-800",
      source_component: "Demos::ApertureComponent"
    },
    {
      slug: "pulse",
      name: "Pulse",
      category: "Data",
      description: "A live analytics board where every tick re-renders server-side SVG charts, gauges, and stat cards through Turbo Streams — no charting library.",
      model: :turbo,
      route: :demos_pulse_path,
      accent: "from-emerald-500 to-teal-700",
      story: "stat_card",
      source_component: "Demos::PulseComponent"
    },
    {
      slug: "flightplan",
      name: "Flightplan",
      category: "Boards",
      description: "A kanban board with optimistic cross-column drag-and-drop, WIP limits, and a no-JavaScript move path — the server always owns the order.",
      model: :turbo,
      route: :demos_flightplan_path,
      accent: "from-sky-600 to-indigo-700",
      story: "kanban_card",
      source_component: "Demos::FlightplanComponent"
    },
    {
      slug: "mission_control",
      name: "Atlas Mission Control",
      category: "Showcase",
      description: "A live command deck with telemetry, a reorderable flight plan, swipe actions, presentations, and signed document workflows.",
      model: :turbo,
      route: :showcase_mission_control_path,
      accent: "from-sky-500 via-blue-600 to-violet-600",
      story: "atlas_mission_control"
    },
    {
      slug: "calculator",
      name: "RPN Calculator",
      category: "Showcase",
      description: "Precise keyboard-first input against a server-owned stack, using a declarative RenderIR key map.",
      model: :turbo,
      route: :showcase_calculator_path,
      accent: "from-amber-500 to-orange-600"
    },
    {
      slug: "commerce",
      name: "Commerce Workflow",
      category: "Showcase",
      description: "A transactional catalog, cart, and checkout built on session state and Turbo Stream updates.",
      model: :turbo,
      route: :showcase_commerce_path,
      accent: "from-lime-500 to-emerald-600"
    },
    {
      slug: "operations",
      name: "Live Operations Room",
      category: "Showcase",
      description: "Signed Action Cable events streaming into a shared operations dashboard in real time.",
      model: :cable,
      route: :showcase_operations_path,
      accent: "from-teal-500 to-cyan-600"
    },
    {
      slug: "rails_first",
      name: "Rails-First Workspace",
      category: "Showcase",
      description: "Conventional CRUD todos, counters, and search where the URL and forms own every piece of state.",
      model: :url,
      route: :rails_first_demo_path,
      accent: "from-rose-500 to-pink-600"
    },
    {
      slug: "workflow",
      name: "Portable Workflows",
      category: "Showcase",
      description: "Route-backed reordering, swipe actions, and validated document flows that work before JavaScript loads.",
      model: :url,
      route: :story_path,
      route_args: { story: "wwdc26_workflows", story_variant: "portable_workflows" },
      accent: "from-indigo-600 to-violet-500",
      story: "wwdc26_workflows"
    }
  ].freeze

  class << self
    def entries
      ENTRIES
    end

    def fetch(slug)
      ENTRIES.find { |entry| entry[:slug] == slug.to_s }
    end

    def by_category
      ENTRIES.group_by { |entry| entry.fetch(:category) }
    end

    def filtered(model)
      key = model.to_s.to_sym
      return ENTRIES unless INTERACTION_MODELS.key?(key)

      ENTRIES.select { |entry| entry.fetch(:model) == key }
    end

    def model_label(model)
      INTERACTION_MODELS.fetch(model)
    end

    # Resolves an entry's destination through the given url_helpers context.
    def path_for(entry, helpers)
      helpers.public_send(entry.fetch(:route), **entry.fetch(:route_args, {}))
    end

    # Server-rendered command registry for the Atlas Command palette: every
    # demo plus fixed navigation targets. The palette only filters what the
    # server rendered — nothing is reachable exclusively through it.
    def palette_commands(helpers)
      ENTRIES.map do |entry|
        {
          label: entry.fetch(:name),
          href: path_for(entry, helpers),
          section: entry.fetch(:category),
          keywords: "#{entry[:slug]} #{model_label(entry.fetch(:model))} #{entry[:description]}"
        }
      end + [
        { label: "Demo gallery", href: helpers.demos_path, section: "Navigate", keywords: "demos index gallery all" },
        { label: "Component lab", href: helpers.rails_stories_path, section: "Navigate", keywords: "storybook stories labs components" },
        { label: "Showcase home", href: helpers.root_path, section: "Navigate", keywords: "home landing start" }
      ]
    end
  end
end
