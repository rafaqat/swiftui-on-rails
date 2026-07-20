# frozen_string_literal: true

require "set"

module SwiftUi
  # Deterministic construction data for the dynamic half of SwiftUi::Lint.
  #
  # Components whose props all have defaults are constructed automatically.
  # Required props are deliberately explicit here: guessing an empty Hash or
  # Array would make linting green while leaving the component's real branches
  # unexecuted. The corpus reuses the same fixed application state objects as
  # the demos and tests, so it performs no I/O and remains stable across runs.
  class LintComponentFixtures
    Case = Data.define(:name, :factory) do
      def build(view_context:)
        factory.call(view_context)
      end
    end

    ABSTRACT_COMPONENTS = %w[
      ApplicationComponent
      SwiftUIComponent
    ].to_set.freeze

    class << self
      def cases_for(component_class)
        explicit = EXPLICIT_FACTORIES[component_class.name]
        return [ Case.new(name: "default", factory: explicit) ] if explicit

        return [] if abstract?(component_class) || required_props(component_class).any?

        [ Case.new(name: "default", factory: ->(_view_context) { component_class.new }) ]
      end

      def abstract?(component_class)
        ABSTRACT_COMPONENTS.include?(component_class.name)
      end

      def required_props(component_class)
        component_class.swift_props.filter_map do |name, definition|
          name if definition[:required]
        end
      end

      def application_component_classes
        component_files.filter_map do |path|
          relative = Pathname.new(path).relative_path_from(Rails.root.join("app/components"))
          relative.to_s.delete_suffix(".rb").camelize.safe_constantize
        end.select do |candidate|
          candidate.is_a?(Class) && candidate < SwiftUIRails::Component::Base
        end.uniq.sort_by(&:name)
      end

      def concrete_component_classes
        application_component_classes.reject { |component_class| abstract?(component_class) }
      end

      def uncovered_component_classes
        concrete_component_classes.select { |component_class| cases_for(component_class).empty? }
      end

      private

      def component_files
        Dir.glob(Rails.root.join("app/components/**/*_component.rb")).sort
      end

      def mission_control_component
        state = Showcase::MissionControlState.new
        AtlasMissionControlComponent.new(
          phase: state.phase,
          sequence_items: state.sequence_items,
          system_items: state.system_items,
          alert_items: state.alert_items,
          telemetry: state.telemetry,
          activity: state.activity,
          summary: {
            readiness: state.readiness,
            hold_count: state.hold_count,
            escalated_alerts: state.escalated_alerts,
            mission_status: state.mission_status
          },
          document: state.document
        )
      end

      def product
        {
          id: "fixture-product",
          name: "Fixture Lamp",
          variant: "Indigo",
          color: "Indigo",
          variant_label: "Indigo",
          price: 49.0,
          original_price: 59.0,
          currency: "$",
          image_url: "/images/placeholder.png",
          in_stock: false,
          on_sale: true,
          rating: 4.5,
          reviews_count: 12
        }
      end

      def variants
        [
          {
            id: "blue",
            type: "color",
            value: "#2563eb",
            label: "Blue",
            hex_color: "#2563eb",
            available: true
          },
          {
            id: "large",
            type: "size",
            value: "L",
            label: "Large",
            available: true
          }
        ]
      end

      def playground_component(view_context)
        example = Showcase::Playground::Examples.find("product-catalog")
        initial_result = Showcase::Playground::Runner.call(
          source: example.source,
          data_json: example.data_json,
          view_context: view_context
        )

        SwiftUiRailsPlaygroundComponent.new(
          examples: Showcase::Playground::Examples.all,
          selected_example: example,
          initial_result: initial_result,
          compile_url: "/showcase/playground/compile"
        )
      end
    end

    EXPLICIT_FACTORIES = {
      "AtlasMissionControlComponent" => ->(_view_context) { mission_control_component },
      "DemoCardComponent" => ->(_view_context) { DemoCardComponent.new(demo: DemoCatalog.entries.first) },
      "Demos::ApertureComponent" => lambda do |_view_context|
        Demos::ApertureComponent.new(
          photos: Demos::ApertureGallery::PHOTOS.first(2),
          active_tag: "sky",
          open_index: 0
        )
      end,
      "Demos::DispatchComponent" => lambda do |_view_context|
        Demos::DispatchComponent.new(
          stations: Demos::DispatchNetwork.stations,
          selected: Demos::DispatchNetwork.stations.first
        )
      end,
      "Demos::FlightplanComponent" => lambda do |_view_context|
        Demos::FlightplanComponent.new(columns: Demos::FlightplanState.new.columns)
      end,
      "Demos::LedgerComponent" => lambda do |_view_context|
        Demos::LedgerComponent.new(result: Demos::LedgerQuery.call({}))
      end,
      "Demos::MotionComponent" => ->(_view_context) { Demos::MotionComponent.new(state: Demos::MotionState.new) },
      "Demos::OnboardComponent" => lambda do |_view_context|
        Demos::OnboardComponent.new(state: Demos::OnboardState.new, step: 1)
      end,
      "Demos::PulseComponent" => lambda do |_view_context|
        snapshot = Demos::PulseTelemetry.snapshot(range: "24h", tick: 0)
        Demos::PulseComponent.new(snapshot: snapshot)
      end,
      "Demos::RelayComponent" => lambda do |_view_context|
        state = Demos::RelayState.new
        selected_thread = state.inbox_threads.first
        Demos::RelayComponent.new(
          threads: state.inbox_threads,
          selected_thread: selected_thread,
          messages: state.messages_for(selected_thread.fetch(:id)),
          archived_count: state.archived_count
        )
      end,
      "EnhancedProductListComponent" => lambda do |_view_context|
        EnhancedProductListComponent.new(products: [ product ])
      end,
      "ImageComponent" => lambda do |_view_context|
        ImageComponent.new(src: "/images/placeholder.png", alt_text: "Fixture image")
      end,
      "KanbanCardComponent" => lambda do |_view_context|
        KanbanCardComponent.new(title: "Fixture card", topic: "ops", priority: "high")
      end,
      "ModalComponent" => lambda do |_view_context|
        ModalComponent.new(open: true, title: "Fixture modal", close_path: "/close")
      end,
      "PaginationComponent" => lambda do |_view_context|
        PaginationComponent.new(current_page: 1, total_pages: 1, base_url: "/products")
      end,
      "ProductCardComponent" => ->(_view_context) { ProductCardComponent.new(product: product) },
      "ProductFilterComponent" => lambda do |_view_context|
        ProductFilterComponent.new(
          filter_options: { color: { "blue" => "Blue" } },
          products_path: "/products"
        )
      end,
      "ProductLayoutComponent" => lambda do |_view_context|
        ProductLayoutComponent.new(products: [ product ], show_filters: false)
      end,
      "ProductListComponent" => ->(_view_context) { ProductListComponent.new(products: [ product ]) },
      "ProductPriceComponent" => lambda do |_view_context|
        ProductPriceComponent.new(price: 49.0, original_price: 59.0)
      end,
      "ProductRatingComponent" => lambda do |_view_context|
        ProductRatingComponent.new(rating: 4.5, show_text: true, interactive: true)
      end,
      "ProductVariantsComponent" => lambda do |_view_context|
        rows = variants
        ProductVariantsComponent.new(variants: rows, selected_variant: rows.first)
      end,
      "SearchComponent" => lambda do |_view_context|
        SearchComponent.new(
          query: "fixture",
          results: [ { title: "Fixture", description: "Result", url: "/result" } ],
          search_path: "/search"
        )
      end,
      "ShowcaseApplicationShellComponent" => lambda do |_view_context|
        ShowcaseApplicationShellComponent.new(page_content: "Fixture body", current_path: "/")
      end,
      "StatCardComponent" => lambda do |_view_context|
        StatCardComponent.new(
          stat_label: "Requests",
          value: "1,204",
          delta: "+4%",
          trend: "up"
        )
      end,
      "SwiftUiRailsPlaygroundComponent" => ->(view_context) { playground_component(view_context) },
      "TabNavigationComponent" => lambda do |_view_context|
        TabNavigationComponent.new(
          tabs: [ { name: "Overview", path: "/overview" } ],
          current_tab: "Overview"
        )
      end,
      "TextComponent" => ->(_view_context) { TextComponent.new(content: "Fixture text") },
      "ToastComponent" => lambda do |_view_context|
        ToastComponent.new(message: "Fixture saved", variant: "success")
      end
    }.freeze
  end
end
