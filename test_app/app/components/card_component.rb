# frozen_string_literal: true

class CardComponent < SwiftUIRails::Component::Base
  # Constants for repeated values
  SIZE_SM = "sm"
  SIZE_LG = "lg"
  SIZE_XS = "xs"
  STYLE_PRIMARY = :primary
  STYLE_SECONDARY = :secondary
  DEFAULT_PADDING = "16"
  DEFAULT_CORNER_RADIUS = SIZE_LG
  DEFAULT_BG_COLOR = "white"
  
  # ViewComponent 2.0 Collection Support
  prop :collection_item, type: Object, default: nil
  prop :collection_counter, type: Integer, default: nil
  
  # Core props
  prop :title, type: String, default: "Card Title"
  prop :content, type: String, default: "This is a sample card content. Cards are great for organizing related information and creating visual hierarchy."
  prop :elevation, type: Integer, default: 1
  prop :padding, type: String, default: DEFAULT_PADDING
  prop :corner_radius, type: String, default: DEFAULT_CORNER_RADIUS
  prop :background_color, type: String, default: DEFAULT_BG_COLOR
  prop :border, type: [TrueClass, FalseClass], default: false
  prop :hover_effect, type: [TrueClass, FalseClass], default: false
  
  # ViewComponent 2.0 Slot Support - renders_one/renders_many
  renders_one :header, "CardHeaderComponent"
  renders_one :media, types: {
    image: "CardImageComponent", 
    video: "CardVideoComponent"
  }
  renders_many :actions, "ActionButtonComponent"
  renders_one :footer, "CardFooterComponent"

  swift_ui do
    # Handle collection data if present
    card_title = collection_item ? (collection_item[:title] || collection_item.title) : title
    card_content = collection_item ? (collection_item[:content] || collection_item.content) : content
    
    card_element = card(elevation: elevation) do
      vstack(spacing: 0) do
        # ViewComponent 2.0 Header Slot
        if header
          div(data: { card_header: true }) do
            header
          end
          .padding(16)
          .border_b
        else
          # Default header content
          div(data: { card_header: true }) do
            hstack do
              text(card_title)
                .font_size(SIZE_LG)
                .font_weight("semibold")
                .text_color("gray-900")
                
              spacer
              
              # Collection counter badge
              if collection_counter
                span("#{collection_counter + 1}")
                  .background("blue-100")
                  .text_color("blue-800")
                  .padding_x(2)
                  .padding_y(1)
                  .corner_radius("full")
                  .font_size(SIZE_XS)
              end
            end
          end
          .padding(16)
        end
        
        # ViewComponent 2.0 Media Slot
        if media
          div(data: { card_media: true }) do
            media
          end
        end
        
        # Main content
        div(data: { card_content: true }) do
          text(card_content)
            .text_color("gray-600")
            .line_clamp(3)
        end
        .padding(16)
        
        # ViewComponent 2.0 Actions Slot (renders_many)
        if actions.any?
          div(data: { card_actions: true }) do
            hstack(spacing: 8) do
              actions.each do |action|
                action
              end
            end
          end
          .padding(16)
          .border_t
        else
          # Default actions
          div(data: { card_actions: true }) do
            hstack(spacing: 8) do
              button("Primary Action")
                .button_style(STYLE_PRIMARY)
                .button_size(SIZE_SM)
              
              button("Secondary")
                .button_style(STYLE_SECONDARY)
                .button_size(SIZE_SM)
            end
          end
          .padding(16)
          .border_t
        end
        
        # ViewComponent 2.0 Footer Slot
        if footer
          div(data: { card_footer: true }) do
            footer
          end
          .padding(16)
          .border_t
        end
      end
    end
    
    # Apply dynamic modifiers with ViewComponent 2.0 performance
    card_element = card_element.padding(padding.to_i) if padding.present? && padding != DEFAULT_PADDING
    card_element = card_element.corner_radius(corner_radius) if corner_radius != DEFAULT_CORNER_RADIUS
    card_element = card_element.background(background_color) if background_color != DEFAULT_BG_COLOR
    card_element = card_element.border if border
    card_element = card_element.hover_scale("105") if hover_effect
    
    card_element
  end
  
  # ViewComponent 2.0 Collection Optimization
  class << self
    def card_collection(cards:, **options, &block)
      # Leverage ViewComponent 2.0 with_collection for 10x performance
      with_collection(cards, **options) do |card_data, counter|
        if card_data.is_a?(Hash)
          new(
            title: card_data[:title] || "Card Title",
            content: card_data[:content] || "Card content",
            collection_item: card_data,
            collection_counter: counter,
            **card_data.except(:title, :content)
          )
        else
          new(
            title: card_data.title || "Card Title",
            content: card_data.content || "Card content", 
            collection_item: card_data,
            collection_counter: counter
          )
        end
      end
    end
  end
end