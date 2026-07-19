# frozen_string_literal: true

class DslCompositionStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers
  
  # Controls for demonstrating composition
  control :items_count, as: :select, options: [3, 5, 10], default: 5
  control :layout, as: :select, options: ["list", "grid"], default: "list"
  control :show_actions, as: :boolean, default: true
  
  def composition_showcase(
    items_count: 5,
    layout: "list",
    show_actions: true
  )
    # Sample data
    products = items_count.times.map do |i|
      {
        id: i + 1,
        name: "Product #{i + 1}",
        description: "High-quality product with amazing features",
        price: "$#{(i + 1) * 10 + 9}.99",
        rating: 4 + (i % 2),
        in_stock: i % 3 != 0
      }
    end
    
    content_tag(:div, class: "p-8") do
      swift_ui do
        vstack(spacing: 24) do
          # Title
          text("SwiftUI-style Composition Pattern")
            .font_size("2xl")
            .font_weight("bold")
            .text_color("gray-900")
          
          text("Favor composition over configuration - build complex UIs from simple, composable parts")
            .text_size("sm")
            .text_color("gray-600")
            .margin_bottom(8)
          
          # List example using the new generic list method
          if layout == "list"
            list(items: products) do |product, index|
              # Each item is composed using simple DSL elements
              card.bg("white") do
                card_content do
                  hstack(spacing: 16, alignment: :start) do
                    # Product image placeholder
                    div
                      .w(20).h(20)
                      .bg("gray-200")
                      .rounded("lg")
                      .flex.items_center.justify_center do
                        text("📦").text_size("2xl")
                      end
                    
                    # Product details
                    vstack(spacing: 2, alignment: :start).flex_grow do
                      hstack(alignment: :center) do
                        text(product[:name])
                          .font_size("lg")
                          .font_weight("semibold")
                          .text_color("gray-900")
                        
                        if product[:in_stock]
                          text("In Stock")
                            .text_size("xs")
                            .text_color("green-600")
                            .bg("green-50")
                            .px(2).py(1)
                            .rounded("full")
                            .ml(2)
                        else
                          text("Out of Stock")
                            .text_size("xs")
                            .text_color("red-600")
                            .bg("red-50")
                            .px(2).py(1)
                            .rounded("full")
                            .ml(2)
                        end
                      end
                      
                      text(product[:description])
                        .text_size("sm")
                        .text_color("gray-600")
                      
                      hstack(spacing: 4, alignment: :center) do
                        text(product[:price])
                          .font_weight("bold")
                          .text_color("blue-600")
                        
                        text("•").text_color("gray-400")
                        
                        # Rating stars
                        hstack(spacing: 1) do
                          product[:rating].times do
                            text("⭐")
                          end
                        end
                      end
                    end
                    
                    # Actions
                    if show_actions
                      vstack(spacing: 2) do
                        button("Add to Cart")
                          .bg("blue-600")
                          .text_color("white")
                          .px(4).py(2)
                          .text_size("sm")
                          .rounded("md")
                          .hover("bg-blue-700")
                          .transition
                        
                        button("View")
                          .bg("gray-100")
                          .text_color("gray-700")
                          .px(4).py(2)
                          .text_size("sm")
                          .rounded("md")
                          .hover("bg-gray-200")
                          .transition
                      end
                    end
                  end
                end
              end.hover("shadow-lg").transition
            end
          else
            # Grid layout example
            grid_list(items: products, columns: 3) do |product, index|
              card.bg("white") do
                card_content do
                  vstack(spacing: 4, alignment: :center) do
                    # Product image placeholder
                    div
                      .w_full.h(32)
                      .bg("gray-100")
                      .rounded("lg")
                      .flex.items_center.justify_center do
                        text("📦").text_size("4xl")
                      end
                    
                    text(product[:name])
                      .font_size("lg")
                      .font_weight("semibold")
                      .text_color("gray-900")
                    
                    text(product[:description])
                      .text_size("sm")
                      .text_color("gray-600")
                      .text_center
                      .line_clamp(2)
                    
                    text(product[:price])
                      .font_size("xl")
                      .font_weight("bold")
                      .text_color("blue-600")
                    
                    if show_actions
                      button("Add to Cart")
                        .bg("blue-600")
                        .text_color("white")
                        .px(4).py(2)
                        .text_size("sm")
                        .rounded("md")
                        .hover("bg-blue-700")
                        .transition
                        .w_full
                    end
                  end
                end
              end.hover("shadow-lg scale-105").transition
            end
          end
        end
      end
    end
  end
  
  def button_composition
    content_tag(:div, class: "p-8") do
      swift_ui do
        vstack(spacing: 16) do
          text("Button Composition Examples")
            .font_size("xl")
            .font_weight("bold")
            .text_color("gray-900")
          
          # Application behavior is declared through Ruby component actions.
          button("Simple Button")
            .bg("blue-600")
            .text_color("white")
            .px(4).py(2)
            .rounded("md")
            .hover("bg-blue-700")
            .transition
          
          # Button with icon composition
          button do
            hstack(spacing: 2, alignment: :center) do
              text("🚀")
              text("Launch")
            end
          end
          .bg("purple-600")
          .text_color("white")
          .px(4).py(2)
          .rounded("md")
          .hover("bg-purple-700")
          .transition
          
          # Button group composition
          hstack(spacing: 0) do
            button("Previous")
              .bg("gray-200")
              .text_color("gray-700")
              .px(4).py(2)
              .rounded("l-md")
              .border_r
              .border_color("gray-300")
              .hover("bg-gray-300")
              .transition
            
            button("1")
              .bg("blue-600")
              .text_color("white")
              .px(4).py(2)
              .hover("bg-blue-700")
              .transition
            
            button("2")
              .bg("gray-200")
              .text_color("gray-700")
              .px(4).py(2)
              .border_l.border_r
              .border_color("gray-300")
              .hover("bg-gray-300")
              .transition
            
            button("Next")
              .bg("gray-200")
              .text_color("gray-700")
              .px(4).py(2)
              .rounded("r-md")
              .border_l
              .border_color("gray-300")
              .hover("bg-gray-300")
              .transition
          end
        end
      end
    end
  end
  
  def card_composition_advanced
    content_tag(:div, class: "p-8") do
      swift_ui do
        vstack(spacing: 16) do
          text("Advanced Card Composition")
            .font_size("xl")
            .font_weight("bold")
            .text_color("gray-900")
          
          # Complex card built from simple parts
          card.bg("white") do
            # Header with actions
            card_header.border_color("gray-200") do
              hstack(alignment: :center) do
                vstack(spacing: 1, alignment: :start).flex_grow do
                  text("Project Dashboard")
                    .font_size("lg")
                    .font_weight("semibold")
                    .text_color("gray-900")
                  
                  text("Last updated 5 minutes ago")
                    .text_size("sm")
                    .text_color("gray-500")
                end
                
                hstack(spacing: 2) do
                  button("Refresh")
                    .bg("white")
                    .text_color("gray-700")
                    .border
                    .border_color("gray-300")
                    .px(3).py(1)
                    .text_size("sm")
                    .rounded("md")
                    .hover("bg-gray-50")
                    .transition
                  
                  button("Settings")
                    .bg("white")
                    .text_color("gray-700")
                    .border
                    .border_color("gray-300")
                    .px(3).py(1)
                    .text_size("sm")
                    .rounded("md")
                    .hover("bg-gray-50")
                    .transition
                end
              end
            end
            
            # Multiple content sections
            card_section do
              grid(columns: 3, spacing: 4) do
                # Metric cards
                [
                  { label: "Total Users", value: "1,234", change: "+12%" },
                  { label: "Revenue", value: "$45,678", change: "+8%" },
                  { label: "Active Projects", value: "42", change: "-2%" }
                ].each do |metric|
                  div
                    .bg("gray-50")
                    .rounded("lg")
                    .p(4) do
                      vstack(spacing: 2, alignment: :start) do
                        text(metric[:label])
                          .text_size("sm")
                          .text_color("gray-600")
                        
                        text(metric[:value])
                          .font_size("2xl")
                          .font_weight("bold")
                          .text_color("gray-900")
                        
                        text(metric[:change])
                          .text_size("sm")
                          .text_color(metric[:change].start_with?("+") ? "green-600" : "red-600")
                      end
                    end
                end
              end
            end
            
            # Chart placeholder
            card_section.border_t.border_color("gray-200") do
              div
                .h(48)
                .bg("gray-50")
                .rounded("lg")
                .flex.items_center.justify_center do
                  text("📊 Chart Visualization")
                    .text_color("gray-400")
                end
            end
            
            # Footer with actions
            card_footer.border_color("gray-200").bg("gray-50") do
              hstack(alignment: :center) do
                text("View detailed analytics")
                  .text_size("sm")
                  .text_color("gray-600")
                  .flex_grow
                
                button("Export")
                  .bg("white")
                  .text_color("gray-700")
                  .border
                  .border_color("gray-300")
                  .px(4).py(2)
                  .text_size("sm")
                  .rounded("md")
                  .hover("bg-gray-50")
                  .transition
                
                button("View All")
                  .bg("blue-600")
                  .text_color("white")
                  .px(4).py(2)
                  .text_size("sm")
                  .rounded("md")
                  .hover("bg-blue-700")
                  .transition
              end
            end
          end
        end
      end
    end
  end
end
