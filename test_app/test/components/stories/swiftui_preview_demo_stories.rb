# frozen_string_literal: true

# This demonstrates the elegance of the SwiftUI-like preview DSL
class SwiftuiPreviewDemoStories < SwiftUIRails::Storybook
  preview "Component Gallery" do
    scenario "Hero Section" do
      # Build complex UIs naturally with composition
      vstack(spacing: 24, alignment: :center) do
        # Hero content
        vstack(spacing: 16, alignment: :center) do
          text("Welcome to SwiftUI Rails")
            .font_size("4xl")
            .font_weight("bold")
            .text_color("gray-900")
          
          text("Build beautiful, interactive UIs with a familiar SwiftUI-like syntax")
            .font_size("lg")
            .text_color("gray-600")
            .max_w("2xl")
            .text_center
          
          # CTA buttons
          hstack(spacing: 4) do
            button("Get Started")
              .bg("blue-600")
              .text_color("white")
              .px(8).py(3)
              .rounded("lg")
              .font_weight("medium")
              .hover("bg-blue-700 scale-105")
              .transition
              .shadow("lg")
            
            button("Learn More")
              .bg("white")
              .text_color("gray-700")
              .border
              .border_color("gray-300")
              .px(8).py(3)
              .rounded("lg")
              .font_weight("medium")
              .hover("bg-gray-50")
              .transition
          end
        end
        
        # Feature cards
        grid(columns: 3, spacing: 8) do
          # Feature 1
          card.bg("white") do
            card_content do
              vstack(spacing: 4, alignment: :center) do
                div.w(12).h(12).bg("blue-100").rounded("full").flex.items_center.justify_center do
                  text("🚀").text_size("2xl")
                end
                
                text("Fast Development")
                  .font_size("lg")
                  .font_weight("semibold")
                  .text_color("gray-900")
                
                text("Build UIs rapidly with our intuitive DSL")
                  .text_size("sm")
                  .text_color("gray-600")
                  .text_center
              end
            end
          end.hover("shadow-lg scale-105").transition
          
          # Feature 2
          card.bg("white") do
            card_content do
              vstack(spacing: 4, alignment: :center) do
                div.w(12).h(12).bg("green-100").rounded("full").flex.items_center.justify_center do
                  text("✨").text_size("2xl")
                end
                
                text("Beautiful by Default")
                  .font_size("lg")
                  .font_weight("semibold")
                  .text_color("gray-900")
                
                text("Tailwind-powered styling that looks great")
                  .text_size("sm")
                  .text_color("gray-600")
                  .text_center
              end
            end
          end.hover("shadow-lg scale-105").transition
          
          # Feature 3
          card.bg("white") do
            card_content do
              vstack(spacing: 4, alignment: :center) do
                div.w(12).h(12).bg("purple-100").rounded("full").flex.items_center.justify_center do
                  text("🎯").text_size("2xl")
                end
                
                text("Type Safe")
                  .font_size("lg")
                  .font_weight("semibold")
                  .text_color("gray-900")
                
                text("Props validation keeps your components reliable")
                  .text_size("sm")
                  .text_color("gray-600")
                  .text_center
              end
            end
          end.hover("shadow-lg scale-105").transition
        end
      end
      .p(8)
      .bg("gray-50")
      .rounded("xl")
    end
    
    scenario "Interactive Form" do
      card.bg("white") do
        card_header do
          text("Create New Project")
            .font_size("xl")
            .font_weight("semibold")
            .text_color("gray-900")
        end
        
        card_content do
          vstack(spacing: 6) do
            # Project name field
            vstack(spacing: 2, alignment: :start) do
              text("Project Name")
                .text_size("sm")
                .font_weight("medium")
                .text_color("gray-700")
              
              input(
                type: "text",
                placeholder: "Enter project name",
                class: "w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              )
            end
            
            # Description field
            vstack(spacing: 2, alignment: :start) do
              text("Description")
                .text_size("sm")
                .font_weight("medium")
                .text_color("gray-700")
              
              textarea(
                placeholder: "Describe your project",
                rows: 3,
                class: "w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              )
            end
            
            # Project type
            vstack(spacing: 2, alignment: :start) do
              text("Project Type")
                .text_size("sm")
                .font_weight("medium")
                .text_color("gray-700")
              
              hstack(spacing: 4) do
                ["Web App", "Mobile App", "API"].each do |type|
                  label(class: "flex items-center space-x-2") do
                    input(type: "radio", name: "project_type", value: type.downcase.gsub(" ", "_"))
                    text(type).text_size("sm").text_color("gray-700")
                  end
                end
              end
            end
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
            
            button("Create Project")
              .bg("blue-600")
              .text_color("white")
              .px(4).py(2)
              .rounded("md")
              .hover("bg-blue-700")
              .transition
          end
        end
      end
      .max_w("lg")
      .shadow("xl")
    end
    
    scenario "Data List" do
      # Sample data
      users = [
        { name: "Sarah Chen", role: "Designer", status: "active" },
        { name: "Mike Johnson", role: "Developer", status: "active" },
        { name: "Emma Davis", role: "Product Manager", status: "away" }
      ]
      
      vstack(spacing: 4) do
        # Header
        hstack(alignment: :center) do
          text("Team Members")
            .font_size("lg")
            .font_weight("semibold")
            .text_color("gray-900")
            .flex_grow
          
          button("Add Member")
            .bg("blue-600")
            .text_color("white")
            .px(3).py(1)
            .text_size("sm")
            .rounded("md")
            .hover("bg-blue-700")
            .transition
        end
        
        # List using the generic list method
        list(items: users) do |user, index|
          div
            .bg("white")
            .border
            .border_color("gray-200")
            .rounded("lg")
            .p(4)
            .hover("shadow-md")
            .transition do
              hstack(alignment: :center) do
                # Avatar
                div
                  .w(10).h(10)
                  .bg("gray-300")
                  .rounded("full")
                  .flex.items_center.justify_center do
                    text(user[:name].split.map(&:first).join)
                      .text_color("white")
                      .font_weight("medium")
                  end
                
                # User info
                vstack(spacing: 0, alignment: :start).flex_grow do
                  text(user[:name])
                    .font_weight("medium")
                    .text_color("gray-900")
                  
                  text(user[:role])
                    .text_size("sm")
                    .text_color("gray-600")
                end
                
                # Status badge
                div
                  .px(2).py(1)
                  .bg(user[:status] == "active" ? "green-100" : "yellow-100")
                  .rounded("full") do
                    text(user[:status].capitalize)
                      .text_size("xs")
                      .text_color(user[:status] == "active" ? "green-800" : "yellow-800")
                  end
              end
            end
        end
      end
      .p(6)
      .bg("gray-50")
      .rounded("xl")
    end
  end
end
