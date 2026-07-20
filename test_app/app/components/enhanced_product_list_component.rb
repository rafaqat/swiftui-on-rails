# frozen_string_literal: true

class EnhancedProductListComponent < SwiftUIRails::Component::Base
  # Core props
  prop :products, type: Array, required: true
  prop :title, type: String, default: "Products"
  prop :columns, type: Symbol, default: :auto
  prop :gap, type: String, default: "6"
  prop :background_color, type: String, default: "white"
  prop :container_padding, type: String, default: "16"
  prop :max_width, type: String, default: "7xl"

  # Animation props
  prop :enable_animations, type: [ TrueClass, FalseClass ], default: true
  prop :animation_delay, type: String, default: "100"
  prop :hover_scale, type: String, default: "105"

  # Sorting props
  prop :sortable, type: [ TrueClass, FalseClass ], default: true
  prop :sort_options, type: Array, default: -> { [ "name", "price", "color" ] }
  prop :default_sort, type: String, default: "name"
  prop :sort_direction, type: String, default: "asc"

  # Filtering props
  prop :filterable, type: [ TrueClass, FalseClass ], default: true
  prop :filter_by_color, type: [ TrueClass, FalseClass ], default: true

  # Display props
  prop :show_quick_actions, type: [ TrueClass, FalseClass ], default: true
  prop :currency_symbol, type: String, default: "$"

  state :active_sort, -> { default_sort }, type: String
  state :active_direction, -> { sort_direction }, type: String
  state :active_color, "all", type: String

  # Slots for maximum flexibility (temporarily disabled for testing)
  # slot :header, required: false
  # slot :product_card, required: false  # Custom product card template
  # slot :empty_state, required: false
  # slot :actions, required: false      # Custom action buttons
  # slot :filters, required: false      # Custom filter controls

  # Grid configurations
  COLUMN_CONFIGS = {
    auto: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4",
    one: "grid-cols-1",
    two: "grid-cols-1 sm:grid-cols-2",
    three: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3",
    four: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4",
    five: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5",
    six: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6"
  }.freeze

  # Animation configurations
  ANIMATION_CONFIGS = {
    fade_in: "animate-fade-in",
    slide_up: "animate-slide-up",
    scale_in: "animate-scale-in",
    stagger: "animate-stagger"
  }.freeze

  swift_ui do
    component = @component

    div(
      data: {
        enhanced_product_list: true,
        sortable: component.sortable,
        filterable: component.filterable
      }
    )
      .bg(component.background_color)
      .transition("colors")
      .duration(500)
      .tw("ease-in-out") do
        div
          .mx("auto")
          .max_w(component.max_width)
          .px(4)
          .py(component.container_padding)
          .sm("px-6")
          .lg("px-8") do
            render_header
            render_controls
            render_products_grid
            render_empty_state
          end
      end
  end

  private

  def render_header
    # if header.present?
    #   header
    # elsif title.present?
    return unless title.present?

    div
      .flex
      .items_center
      .justify_between
      .mb(6) do
        h2(title)
          .text_size("2xl")
          .font_weight("bold")
          .tracking("tight")
          .text_color("gray-900")
      end
  end

  def render_controls
    return unless sortable || filterable

    div
      .mb(6)
      .flex
      .flex_wrap
      .items_center
      .gap(4) do
        render_sort_controls
        render_filter_controls
      end
  end

  def render_sort_controls
    return unless sortable

    div.flex.items_center.gap(2) do
      label("Sort by:")
        .text_size("sm")
        .font_weight("medium")
        .text_color("gray-700")

      sort_picker = select do
        sort_options.each do |sort_option|
          option(sort_option, sort_option.humanize, selected: sort_option == active_sort)
        end
      end
      sort_picker.on_change do |event|
        self.active_sort = event.value.to_s if sort_options.include?(event.value.to_s)
      end
      sort_picker
        .rounded("md")
        .border_color("gray-300")
        .text_size("sm")
        .focus_border_color("blue-500")
        .focus_ring_color("blue-500")

      direction_button = button(aria: { label: "Reverse sort direction" }) do
        svg_element(viewBox: "0 0 20 20", fill: "currentColor") do
          path_element(
            fill_rule: "evenodd",
            d: "M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z",
            clip_rule: "evenodd"
          )
        end.w(4).h(4)
      end
        .p(2)
        .rounded("md")
        .border
        .border_color("gray-300")
        .hover_bg("gray-50")
        .transition("colors")
      direction_button.on_click do
        self.active_direction = active_direction == "asc" ? "desc" : "asc"
      end
    end
  end

  def render_filter_controls
    return unless filterable && filter_by_color

    colors = products.map { |p| product_color(p) }.compact.uniq.sort
    return if colors.empty?

    div.flex.items_center.gap(2) do
      label("Filter:")
        .text_size("sm")
        .font_weight("medium")
        .text_color("gray-700")

      div.flex.gap(1) do
        color_filter_button("All", "all")
        colors.each { |color| color_filter_button(color, color) }
      end
    end
  end

  def render_products_grid
    div(data: { product_grid: true })
      .grid_class
      .gap(gap)
      .transition("[grid-template-columns,gap]")
      .duration(700)
      .tw("ease-in-out", COLUMN_CONFIGS[columns] || COLUMN_CONFIGS[:auto]) do
      if visible_products.any?
        visible_products.each_with_index { |product, index| render_product_card(product, index) }
      end
    end
  end

  def render_empty_state
    empty = div(data: { product_empty_state: true }) do
      div.text_color("gray-400").mb(4) do
        svg_element(fill: "none", viewBox: "0 0 24 24", stroke: "currentColor") do
          path_element(
            stroke_linecap: "round",
            stroke_linejoin: "round",
            stroke_width: "2",
            d: "M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2 2v-5m16 0h-2M4 13h2"
          )
        end
          .mx("auto")
          .h(12)
          .w(12)
      end

      h3("No products found")
        .text_size("lg")
        .font_weight("medium")
        .text_color("gray-900")
        .mb(2)
      p("Try adjusting your filters or search criteria.").text_color("gray-500")
    end
    empty.text_center.py(12)
    empty.gone if visible_products.any?
    empty
  end

  def render_product_card(product, index)
    # card_content = if product_card.present?
    #   # Use custom product card slot
    #   product_card.call(product: product, index: index)
    # else
    #   # Default product card implementation
    #   render_default_product_card(product, index)
    # end

    div(
      data: {
        product_card: true,
        "product-id": product_id(product),
        "product-name": product_name(product),
        "product-price": product_price(product),
        "product-color": product_color(product)
      }
    ) do
      render_default_product_card(product, index)
    end
      .relative
      .tw("transform-gpu")
      .hover("scale-#{enable_animations ? hover_scale : '102'} z-10")
  end

  def render_default_product_card(product, index)
    div.group.relative do
      div
        .relative
        .overflow("hidden")
        .rounded("lg") do
          link(destination: product_url(product)) do
            image(src: product_image_url(product), alt: product_alt_text(product))
              .aspect("square")
              .w_full
              .rounded("md")
              .bg("gray-200")
              .object("cover")
              .transition("transform")
              .duration(300)
              .tw("ease-out")
              .group_hover("scale-105")
          end.block.h("full")

          render_quick_actions(product) if show_quick_actions
        end

      div.mt(4).space_y(2).min_h("[60px]") do
        div.flex.justify_between.items_start.gap(2) do
          div.flex_1.min_w(0) do
            h3
              .text_size("sm")
              .font_weight("medium")
              .text_color("gray-900")
              .tw("truncate")
              .leading("tight") do
                link(product_name(product), destination: product_url(product))
                  .hover_text_color("blue-600")
                  .transition("colors")
                  .duration(200)
              end

            if product_color(product).present?
              p(product_color(product))
                .text_size("xs")
                .text_color("gray-500")
                .mt(1)
                .leading("tight")
            end
          end

          p(formatted_price(product))
            .text_size("sm")
            .font_weight("semibold")
            .text_color("gray-900")
            .tw("whitespace-nowrap")
        end
      end
    end
  end

  def render_quick_actions(product)
    div do
      div.flex.gap(2) do
        quick_action_link(
          product,
          path: "M15 12a3 3 0 11-6 0 3 3 0 016 0z M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
        )
      end
    end
      .absolute
      .inset(0)
      .bg("black/0")
      .group_hover("bg-black/20")
      .transition("opacity")
      .duration(300)
      .flex
      .items_center
      .justify_center
      .opacity(0)
      .group_hover("opacity-100")
  end

  def color_filter_button(label, color)
    filter = button(label, data: { color: color })
    filter.on_click { self.active_color = color }
    filter
      .px(3)
      .py(1)
      .text_size("xs")
      .rounded("full")
      .border
      .border_color("gray-300")
      .hover_bg("gray-50")
      .transition("colors")
  end

  def quick_action_link(product, path:)
    a(href: product_url(product), aria: { label: "Inspect #{product_name(product)}" }, data: { product_id: product_id(product) }) do
      svg_element(fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        path_element(
          stroke_linecap: "round",
          stroke_linejoin: "round",
          stroke_width: "2",
          d: path
        )
      end.w(4).h(4)
    end
      .p(2)
      .bg("white")
      .rounded("full")
      .shadow("lg")
      .hover_bg("gray-50")
      .transition("transform")
      .duration(200)
      .transform
      .hover("scale-110")
  end

  def visible_products
    selected = active_color == "all" ? products : products.select { |product| product_color(product) == active_color }
    ordered = selected.sort_by do |product|
      case active_sort
      when "price" then product_price(product).to_f
      when "color" then product_color(product).to_s.downcase
      else product_name(product).to_s.downcase
      end
    end
    active_direction == "desc" ? ordered.reverse : ordered
  end

  def svg_element(**attributes, &block)
    create_element(:svg, nil, attributes, &block)
  end

  def path_element(**attributes)
    create_element(:path, "", attributes)
  end

  # Data extraction methods (same as before)
  def product_name(product)
    product.try(:name) || product.try(:title) || product[:name] || product[:title] || "Product"
  end

  def product_image_url(product)
    product.try(:image_url) || product.try(:image) || product[:image_url] || product[:image] || "https://via.placeholder.com/400x400?text=No+Image"
  end

  def product_url(product)
    if product.respond_to?(:id)
      "/products/#{product.id}"
    elsif product[:id]
      "/products/#{product[:id]}"
    else
      "#"
    end
  end

  def product_color(product)
    product.try(:color) || product.try(:variant) || product[:color] || product[:variant]
  end

  def product_price(product)
    product.try(:price) || product[:price] || 0
  end

  def product_id(product)
    # product_id is read separately for the card data and the quick-action
    # link, so an id-less product must reuse the same generated id across both
    # calls within a render — otherwise the two data-product-id values diverge.
    product.try(:id) || product[:id] || generated_product_ids[product.object_id]
  end

  def generated_product_ids
    @generated_product_ids ||= Hash.new { |ids, key| ids[key] = SecureRandom.hex(4) }
  end

  def product_alt_text(product)
    name = product_name(product)
    color = product_color(product)
    if color.present?
      "#{name} in #{color}"
    else
      name
    end
  end

  def formatted_price(product)
    price = product_price(product)
    if price.is_a?(Numeric)
      "#{currency_symbol}#{price}"
    else
      price.to_s
    end
  end
end
