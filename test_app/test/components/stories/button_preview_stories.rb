# frozen_string_literal: true

# This demonstrates the new SwiftUI-like preview DSL
class ButtonPreviewStories < SwiftUIRails::Storybook
  # Controls are still defined at the class level for interactive Storybook
  control :variant, as: :select, options: ["primary", "secondary", "danger", "success"], default: "primary"
  control :size, as: :select, options: ["sm", "md", "lg", "xl"], default: "md"
  control :disabled, as: :boolean, default: false
  
  preview "Button Variations" do
    scenario "Primary Button" do
      # You use the DSL directly! No more `.new` or `render`.
      button("Primary Button")
        .bg("blue-600")
        .text_color("white")
        .px(4).py(2)
        .rounded("md")
        .hover("bg-blue-700")
        .transition
    end
    
    scenario "Secondary Button" do
      button("Secondary Button")
        .bg("gray-200")
        .text_color("gray-900")
        .px(4).py(2)
        .rounded("md")
        .hover("bg-gray-300")
        .transition
    end
    
    scenario "Danger Button" do
      button("Delete Account")
        .bg("red-600")
        .text_color("white")
        .px(4).py(2)
        .rounded("md")
        .hover("bg-red-700")
        .transition
        .disabled
    end
    
    # Composition is natural and easy
    scenario "Button Group" do
      hstack(spacing: 4, alignment: :center) do
        button("Save")
          .bg("green-600")
          .text_color("white")
          .px(4).py(2)
          .rounded("l-md")
          .hover("bg-green-700")
          .transition
        
        button("Save & Continue")
          .bg("green-700")
          .text_color("white")
          .px(4).py(2)
          .rounded("r-md")
          .hover("bg-green-800")
          .transition
      end
    end
    
    scenario "Button with Icon" do
      button do
        hstack(spacing: 2, alignment: :center) do
          text("🚀")
          text("Launch Application")
        end
      end
      .bg("purple-600")
      .text_color("white")
      .px(6).py(3)
      .rounded("lg")
      .hover("bg-purple-700 scale-105")
      .transition
      .shadow("lg")
    end
  end
  
  preview "Interactive Buttons" do
    scenario "Loading State" do
      vstack(spacing: 4) do
        button("Submit")
          .bg("blue-600")
          .text_color("white")
          .px(4).py(2)
          .rounded("md")
          .hover("bg-blue-700")
          .transition
        
        button do
          hstack(spacing: 2, alignment: :center) do
            spinner(size: :sm, border_color: "white/20", spinner_color: "white")
            text("Processing...")
          end
        end
        .bg("blue-600")
        .text_color("white")
        .px(4).py(2)
        .rounded("md")
        .opacity(75)
        .cursor("not-allowed")
        .disabled
      end
    end
    
    scenario "Toggle Button" do
      hstack(spacing: 0) do
        button("Grid View")
          .bg("white")
          .text_color("gray-700")
          .border
          .border_color("gray-300")
          .px(4).py(2)
          .rounded("l-md")
          .hover("bg-gray-50")
          .transition
        
        button("List View")
          .bg("blue-600")
          .text_color("white")
          .border
          .border_color("blue-600")
          .px(4).py(2)
          .rounded("r-md")
          .hover("bg-blue-700")
          .transition
      end
    end
  end
  
  preview "Advanced Compositions" do
    scenario "Card with Actions" do
      card.bg("white") do
        card_content do
          vstack(spacing: 4) do
            text("Confirm Action")
              .font_size("lg")
              .font_weight("semibold")
              .text_color("gray-900")
            
            text("Are you sure you want to proceed? This action cannot be undone.")
              .text_size("sm")
              .text_color("gray-600")
          end
        end
        
        card_footer do
          hstack(spacing: 3, alignment: :center) do
            button("Cancel")
              .bg("white")
              .text_color("gray-700")
              .border
              .border_color("gray-300")
              .px(4).py(2)
              .rounded("md")
              .hover("bg-gray-50")
              .transition
              .flex_grow
            
            button("Confirm")
              .bg("blue-600")
              .text_color("white")
              .px(4).py(2)
              .rounded("md")
              .hover("bg-blue-700")
              .transition
              .flex_grow
          end
        end
      end
      .max_w("sm")
      .shadow("xl")
    end
    
    scenario "Floating Action Button" do
      div.relative.h(64).w_full.bg("gray-100").rounded("lg") do
        # Content area
        div.p(4) do
          text("Content Area")
            .text_color("gray-500")
        end
        
        # Floating button
        button do
          text("➕")
            .text_size("xl")
        end
        .absolute
        .bottom(4)
        .right(4)
        .bg("blue-600")
        .text_color("white")
        .w(14).h(14)
        .rounded("full")
        .shadow("lg")
        .hover("bg-blue-700 shadow-xl scale-110")
        .transition
        .flex.items_center.justify_center
      end
    end
  end
end
