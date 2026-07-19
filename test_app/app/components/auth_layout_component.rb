# frozen_string_literal: true

class AuthLayoutComponent < ApplicationComponent
  # Layout configuration
  prop :variant, type: Symbol, default: :centered # :centered, :split, :card
  prop :background_color, type: String, default: "gray-50"
  prop :show_logo, type: [TrueClass, FalseClass], default: true
  prop :logo_url, type: String, default: nil
  prop :brand_name, type: String, default: "Your Brand"
  prop :show_footer, type: [TrueClass, FalseClass], default: true
  
  # Content slots
  renders_one :form
  renders_one :sidebar
  renders_one :header
  renders_one :footer
  
  swift_ui do
    case variant
    when :centered
      centered_layout
    when :split
      split_layout
    when :card
      card_layout
    else
      centered_layout
    end
  end
  
  private
  
  def centered_layout
    div.min_h("screen").flex.flex_col.justify_center.py(12).sm("px-6 lg:px-8").bg(background_color) do
      # Logo/Brand
      if show_logo
        div.sm("mx-auto sm:w-full sm:max-w-md") do
          if logo_url
            image(src: logo_url, alt: brand_name)
              .mx("auto")
              .h(12)
              .w("auto")
          else
            h2(brand_name)
              .text_center
              .text_size("3xl")
              .font_weight("extrabold")
              .text_color("gray-900")
          end
        end
      end
      
      # Custom header
      if header?
        div.mt(8).sm("mx-auto sm:w-full sm:max-w-md") do
          header
        end
      end
      
      # Main form content
      div.mt(8).sm("mx-auto sm:w-full sm:max-w-md") do
        div.bg("white").py(8).px(4).shadow("xl").sm("rounded-lg sm:px-10") do
          form if form?
        end
      end
      
      # Footer
      if show_footer || footer?
        div.mt(8).sm("mx-auto sm:w-full sm:max-w-md") do
          if footer?
            footer
          else
            default_footer
          end
        end
      end
    end
  end
  
  def split_layout
    div.min_h("screen").flex do
      # Left side - Form
      div.flex.flex_1.flex_col.justify_center.py(12).px(4).sm("px-6 lg:px-8").bg("white") do
        div.mx("auto").w_full.max_w("sm") do
          # Logo
          if show_logo && !logo_url
            h2(brand_name)
              .text_size("3xl")
              .font_weight("extrabold")
              .text_color("gray-900")
              .mb(8)
          end
          
          # Form
          form if form?
          
          # Footer for mobile
          if show_footer || footer?
            div.mt(8).block.lg("hidden") do
              if footer?
                footer
              else
                default_footer
              end
            end
          end
        end
      end
      
      # Right side - Sidebar/Image
      div.hidden.lg("block relative w-0 flex-1") do
        if sidebar?
          sidebar
        else
          # Default gradient background
          div.absolute.inset(0).bg_gradient_to_r.from("indigo-500").to("purple-600") do
            div.absolute.inset(0).bg("black").opacity(20)
            div.absolute.inset(0).flex.items_center.justify_center.p(12) do
              div.max_w("md").text_center do
                h3("Welcome to #{brand_name}")
                  .text_size("4xl")
                  .font_weight("bold")
                  .text_color("white")
                  .mb(4)
                p("Join thousands of users who trust us with their business")
                  .text_size("xl")
                  .text_color("white")
                  .opacity(90)
              end
            end
          end
        end
      end
    end
  end
  
  def card_layout
    div.min_h("screen").flex.items_center.justify_center.bg(background_color).px(4).py(12) do
      div.w_full.max_w("lg").space_y(8) do
        # Logo/Brand centered
        if show_logo
          div.text_center do
            if logo_url
              image(src: logo_url, alt: brand_name)
                .mx("auto")
                .h(16)
                .w("auto")
            else
              h1(brand_name)
                .text_size("4xl")
                .font_weight("extrabold")
                .text_color("gray-900")
            end
          end
        end
        
        # Card container
        div.bg("white").shadow("2xl").rounded("xl").overflow("hidden") do
          # Optional header
          if header?
            div.bg("gray-50").px(8).py(6).border_b.border_color("gray-200") do
              header
            end
          end
          
          # Form content
          div.p(8) do
            form if form?
          end
          
          # Optional footer in card
          if footer?
            div.bg("gray-50").px(8).py(6).border_t.border_color("gray-200") do
              footer
            end
          end
        end
        
        # External footer
        if show_footer && !footer?
          default_footer
        end
      end
    end
  end
  
  def default_footer
    div.text_center.text_size("sm").text_color("gray-600") do
      text("© #{Date.current.year} #{brand_name}. All rights reserved.")
      div.mt(2).space_x(4) do
        link("Privacy Policy", destination: "/privacy")
          .text_color("gray-600")
          .hover_text_color("gray-900")
        span("•").text_color("gray-400")
        link("Terms of Service", destination: "/terms")
          .text_color("gray-600")
          .hover_text_color("gray-900")
        span("•").text_color("gray-400")
        link("Contact Support", destination: "/support")
          .text_color("gray-600")
          .hover_text_color("gray-900")
      end
    end
  end
end
