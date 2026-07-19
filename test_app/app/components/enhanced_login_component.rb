# frozen_string_literal: true

class EnhancedLoginComponent < ApplicationComponent
  # Form configuration
  prop :action, type: String, default: "/login"
  prop :method, type: String, default: "post"
  prop :email, type: String, default: ""
  prop :errors, type: Hash, default: {}
  prop :general_error, type: String, default: nil
  prop :show_social, type: [TrueClass, FalseClass], default: true
  
  swift_ui do
    div do
      # Container
      div.max_w("md").w_full.bg("white").shadow("xl").rounded("lg").p(8) do
        # Logo/Brand
        div.text_center.mb(8) do
          div.mx("auto").h(12).w(12).bg("indigo-600").rounded("full").flex.items_center.justify_center do
            text("A").text_color("white").font_size("xl").font_weight("bold")
          end
          h2("Welcome back").mt(4).text_size("2xl").font_weight("bold").text_color("gray-900")
          text("Sign in to your account").mt(2).text_size("sm").text_color("gray-600")
        end
        
        # Error Alert
        if general_error
          div.bg("red-50").border.border_color("red-200").text_color("red-700").px(4).py(3).rounded("md").mb(6) do
            text(general_error).text_size("sm")
          end
        end
        
        # Form
        form(action: component.action, method: component.method, data: { turbo: false }) do
          div.space_y(6) do
            # Email Field
            div do
              label("Email", for: "email").block.text_size("sm").font_weight("medium").text_color("gray-700")
              input(
                type: "email",
                id: "email",
                name: "email",
                value: email,
                required: true,
                placeholder: "you@example.com"
              )
              .mt(1)
              .block
              .w_full
              .px(3)
              .py(2)
              .border
              .border_color(errors[:email] ? "red-300" : "gray-300")
              .rounded("md")
              .shadow("sm")
              .focus("ring-indigo-500 border-indigo-500")
              .sm("text-sm")
              
              if errors[:email]
                text(errors[:email].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Password Field
            div do
              label("Password", for: "password").block.text_size("sm").font_weight("medium").text_color("gray-700")
              input(
                type: "password",
                id: "password",
                name: "password",
                required: true,
                placeholder: "••••••••"
              )
              .mt(1)
              .block
              .w_full
              .px(3)
              .py(2)
              .border
              .border_color(errors[:password] ? "red-300" : "gray-300")
              .rounded("md")
              .shadow("sm")
              .focus("ring-indigo-500 border-indigo-500")
              .sm("text-sm")
              
              if errors[:password]
                text(errors[:password].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Remember & Forgot
            div.flex.items_center.justify_between do
              div.flex.items_center do
                input(type: "checkbox", id: "remember", name: "remember", value: "1")
                  .h(4).w(4).text_color("indigo-600").focus("ring-indigo-500").border_color("gray-300").rounded
                label("Remember me", for: "remember").ml(2).block.text_size("sm").text_color("gray-900")
              end
              
              div.text_size("sm") do
                link("Forgot password?", destination: "/forgot-password")
                  .font_weight("medium")
                  .text_color("indigo-600")
                  .hover_text_color("indigo-500")
              end
            end
            
            # Submit Button
            div do
              button("Sign in", type: "submit")
                .w_full
                .flex
                .justify_center
                .py(2)
                .px(4)
                .border
                .border_color("transparent")
                .rounded("md")
                .shadow("sm")
                .text_size("sm")
                .font_weight("medium")
                .text_color("white")
                .bg("indigo-600")
                .hover_bg("indigo-700")
                .focus("outline-none ring-2 ring-offset-2 ring-indigo-500")
            end
          end
        end
        
        # Social Login
        if show_social
          div.mt(6) do
            div.relative do
              div.absolute.inset(0).flex.items_center do
                div.w_full.border_t.border_color("gray-300")
              end
              div.relative.flex.justify_center.text_size("sm") do
                span("Or continue with").px(2).bg("white").text_color("gray-500")
              end
            end
            
            div.mt(6).grid.grid_cols(2).gap(3) do
              button(type: "button")
                .w_full
                .inline_flex
                .justify_center
                .py(2)
                .px(4)
                .border
                .border_color("gray-300")
                .rounded("md")
                .shadow("sm")
                .bg("white")
                .text_size("sm")
                .font_weight("medium")
                .text_color("gray-500")
                .hover_bg("gray-50") do
                text("Google")
              end
              
              button(type: "button")
                .w_full
                .inline_flex
                .justify_center
                .py(2)
                .px(4)
                .border
                .border_color("gray-300")
                .rounded("md")
                .shadow("sm")
                .bg("white")
                .text_size("sm")
                .font_weight("medium")
                .text_color("gray-500")
                .hover_bg("gray-50") do
                text("GitHub")
              end
            end
          end
        end
      end
    end
    .min_h("screen")
    .flex
    .items_center
    .justify_center
    .bg("gray-50")
    .py(12)
    .px(4)
    .sm("px-6 lg:px-8")
  end
end
