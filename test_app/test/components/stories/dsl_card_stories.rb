# frozen_string_literal: true

class DslCardStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers
  
  control :card_title, as: :text, default: "Card Title"
  control :card_content, as: :text, default: "This is some card content that demonstrates the DSL capabilities."
  control :elevation, as: :select, options: [1, 2, 3], default: 2
  control :background, as: :select, options: ["white", "gray-50", "blue-50", "green-50"], default: "white"
  control :border_color, as: :select, options: ["gray-200", "blue-200", "green-200", "purple-200"], default: "gray-200"
  
  def default(
    card_title: "Card Title",
    card_content: "This is some card content that demonstrates the DSL capabilities.",
    elevation: 2,
    background: "white",
    border_color: "gray-200"
  )
    content_tag(:div, class: "p-8") do
      swift_ui do
        vstack(spacing: 16) do
          text("DSL Card - Composition Pattern")
            .font_size("xl")
            .font_weight("bold")
            .text_color("gray-900")
            .margin_bottom(4)
          
          # Card using manual div to allow background customization
          div
            .tw("rounded-lg shadow-md")
            .bg(background)
            .border.border_color(border_color)
            .shadow(elevation == 1 ? "" : elevation == 2 ? "md" : "lg")
            .max_w("md")
            .hover("shadow-xl")
            .transition do
            
            card_header do
              text(card_title)
                .font_size("lg")
                .font_weight("semibold")
                .text_color("gray-900")
            end
            
            card_content do
              text(card_content)
                .text_color("gray-600")
                .line_clamp(3)
            end
            
            card_footer do
              hstack(spacing: 4, alignment: :center) do
                button("Learn More")
                  .bg("blue-600")
                  .text_color("white")
                  .px(4).py(2)
                  .text_size("sm")
                  .rounded("md")
                  .hover("bg-blue-700")
                  .transition
                
                button("Dismiss")
                  .bg("gray-200")
                  .text_color("gray-700")
                  .px(4).py(2)
                  .text_size("sm")
                  .rounded("md")
                  .hover("bg-gray-300")
                  .transition
              end
            end
          end
        end
      end
    end
  end
  
  def card_gallery
    content_tag(:div, class: "p-8") do
      swift_ui do
        vstack(spacing: 16) do
          text("DSL Card Gallery")
            .font_size("2xl")
            .font_weight("bold")
            .text_color("gray-900")
            .margin_bottom(8)
          
          # Card variations
          grid(columns: 3, spacing: 6) do
            # Simple card
            div
              .bg("white")
              .border
              .border_color("gray-200")
              .rounded("lg")
              .shadow("md")
              .padding(6)
              .hover("shadow-lg")
              .transition do
                vstack(spacing: 4, alignment: :start) do
                  text("Simple Card")
                    .font_size("lg")
                    .font_weight("semibold")
                    .text_color("gray-900")
                  
                  text("Basic card with hover effect")
                    .text_color("gray-600")
                    .text_size("sm")
                end
              end
            
            # Interactive card
            div do
              vstack(spacing: 4, alignment: :start) do
                text("Interactive Card")
                  .font_size("lg")
                  .font_weight("semibold")
                  .text_color("blue-900")

                text("Application behavior is declared as a Ruby action")
                  .text_color("blue-600")
                  .text_size("sm")
              end
            end
              .bg("blue-50")
              .border
              .border_color("blue-200")
              .rounded("lg")
              .shadow("md")
              .padding(6)
              .hover("bg-blue-100")
              .cursor("pointer")
              .transition
            
            # Feature card
            div
              .tw("bg-gradient-to-br from-purple-50 to-pink-50")
              .border
              .border_color("purple-200")
              .rounded("xl")
              .shadow("lg")
              .padding(6)
              .hover("scale-105")
              .transition do
                vstack(spacing: 4, alignment: :center) do
                  div
                    .w(12).h(12)
                    .bg("purple-600")
                    .rounded("full")
                    .flex
                    .items_center
                    .justify_center
                    .margin_bottom(2) do
                      text("🚀")
                        .text_size("lg")
                    end
                  
                  text("Feature Card")
                    .font_size("lg")
                    .font_weight("bold")
                    .text_color("purple-900")
                  
                  text("With icon and gradient")
                    .text_color("purple-600")
                    .text_size("sm")
                    .text_center
                end
              end
          end
        end
      end
    end
  end
end
