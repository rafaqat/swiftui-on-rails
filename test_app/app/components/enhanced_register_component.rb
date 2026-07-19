# frozen_string_literal: true

class EnhancedRegisterComponent < ApplicationComponent
  # Form configuration
  prop :action, type: String, default: "/register"
  prop :method, type: String, default: "post"
  prop :name, type: String, default: ""
  prop :email, type: String, default: ""
  prop :errors, type: Hash, default: {}
  prop :general_error, type: String, default: nil
  prop :terms_path, type: String, default: "/terms"
  prop :privacy_path, type: String, default: "/privacy"
  
  swift_ui do
    div do
      # Container
      div.max_w("md").w_full.bg("white").shadow("xl").rounded("lg").p(8) do
        # Header
        div.text_center.mb(8) do
          div.mx("auto").h(12).w(12).bg("green-600").rounded("full").flex.items_center.justify_center do
            text("✓").text_color("white").font_size("xl").font_weight("bold")
          end
          h2("Create your account").mt(4).text_size("2xl").font_weight("bold").text_color("gray-900")
          text("Start your journey with us").mt(2).text_size("sm").text_color("gray-600")
        end
        
        # Progress indicator
        div.mb(8) do
          div.flex.items_center do
            # Step 1 - Active
            div.flex.items_center.flex_1 do
              div.w(10).h(10).bg("indigo-600").rounded("full").flex.items_center.justify_center do
                text("1").text_color("white").text_size("sm").font_weight("bold")
              end
              text("Account").ml(3).text_size("sm").font_weight("medium").text_color("indigo-600")
            end
            
            # Connector
            div.flex_1.h(0.5).bg("gray-300").mx(4)
            
            # Step 2 - Inactive
            div.flex.items_center.flex_1 do
              div.w(10).h(10).bg("gray-300").rounded("full").flex.items_center.justify_center do
                text("2").text_color("gray-500").text_size("sm").font_weight("medium")
              end
              text("Verify").ml(3).text_size("sm").text_color("gray-500")
            end
          end
        end
        
        # Error Alert
        if general_error
          div.bg("red-50").border.border_color("red-200").text_color("red-700").px(4).py(3).rounded("md").mb(6).flex.items_start do
            span("⚠").mr(2).text_color("red-600")
            div do
              text("Error creating account").font_weight("medium")
              text(general_error).block.text_size("sm").mt(1)
            end
          end
        end
        
        # Form
        form(action: component.action, method: component.method, data: { turbo: false }) do
          div.space_y(6) do
            # Name Field
            div do
              label("Full name", for: "name").block.text_size("sm").font_weight("medium").text_color("gray-700")
              div.mt(1).relative.rounded("md").shadow("sm") do
                div.absolute.inset_y(0).left(0).pl(3).flex.items_center.pointer_events_none do
                  span("👤").text_color("gray-400")
                end
                input(
                  type: "text",
                  id: "name",
                  name: "name",
                  value: name,
                  required: true,
                  placeholder: "John Doe"
                )
                .block
                .w_full
                .pl(10)
                .pr(3)
                .py(2)
                .border
                .border_color(errors[:name] ? "red-300" : "gray-300")
                .rounded("md")
                .focus("ring-indigo-500 border-indigo-500")
                .sm("text-sm")
              end
              
              if errors[:name]
                text(errors[:name].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Email Field
            div do
              label("Email address", for: "email").block.text_size("sm").font_weight("medium").text_color("gray-700")
              div.mt(1).relative.rounded("md").shadow("sm") do
                div.absolute.inset_y(0).left(0).pl(3).flex.items_center.pointer_events_none do
                  span("✉").text_color("gray-400")
                end
                input(
                  type: "email",
                  id: "email",
                  name: "email",
                  value: email,
                  required: true,
                  placeholder: "you@example.com"
                )
                .block
                .w_full
                .pl(10)
                .pr(3)
                .py(2)
                .border
                .border_color(errors[:email] ? "red-300" : "gray-300")
                .rounded("md")
                .focus("ring-indigo-500 border-indigo-500")
                .sm("text-sm")
              end
              
              if errors[:email]
                text(errors[:email].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Password Field
            div do
              label("Password", for: "password").block.text_size("sm").font_weight("medium").text_color("gray-700")
              div.mt(1).relative.rounded("md").shadow("sm") do
                div.absolute.inset_y(0).left(0).pl(3).flex.items_center.pointer_events_none do
                  span("🔒").text_color("gray-400")
                end
                input(
                  type: "password",
                  id: "password",
                  name: "password",
                  required: true,
                  placeholder: "••••••••"
                )
                .block
                .w_full
                .pl(10)
                .pr(3)
                .py(2)
                .border
                .border_color(errors[:password] ? "red-300" : "gray-300")
                .rounded("md")
                .focus("ring-indigo-500 border-indigo-500")
                .sm("text-sm")
              end
              
              # Password strength indicator
              div.mt(2) do
                div.text_size("xs").text_color("gray-600").mb(1) do
                  text("Password strength")
                end
                div.flex.space_x(1) do
                  div.flex_1.h(2).bg("gray-200").rounded("full")
                  div.flex_1.h(2).bg("gray-200").rounded("full")
                  div.flex_1.h(2).bg("gray-200").rounded("full")
                  div.flex_1.h(2).bg("gray-200").rounded("full")
                end
              end
              
              if errors[:password]
                text(errors[:password].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Password Confirmation
            div do
              label("Confirm password", for: "password_confirmation").block.text_size("sm").font_weight("medium").text_color("gray-700")
              div.mt(1).relative.rounded("md").shadow("sm") do
                div.absolute.inset_y(0).left(0).pl(3).flex.items_center.pointer_events_none do
                  span("🔒").text_color("gray-400")
                end
                input(
                  type: "password",
                  id: "password_confirmation",
                  name: "password_confirmation",
                  required: true,
                  placeholder: "••••••••"
                )
                .block
                .w_full
                .pl(10)
                .pr(3)
                .py(2)
                .border
                .border_color(errors[:password_confirmation] ? "red-300" : "gray-300")
                .rounded("md")
                .focus("ring-indigo-500 border-indigo-500")
                .sm("text-sm")
              end
              
              if errors[:password_confirmation]
                text(errors[:password_confirmation].first).mt(2).text_size("sm").text_color("red-600")
              end
            end
            
            # Terms checkbox
            div.flex.items_start do
              div.flex.items_center.h(5) do
                input(type: "checkbox", id: "terms", name: "terms", value: "1", required: true)
                  .h(4).w(4).text_color("indigo-600").focus("ring-indigo-500").border_color("gray-300").rounded
              end
              div.ml(3).text_size("sm") do
                label(for: "terms").text_color("gray-700") do
                  text("I agree to the ")
                  link("Terms", destination: terms_path).text_color("indigo-600").hover_text_color("indigo-500")
                  text(" and ")
                  link("Privacy Policy", destination: privacy_path).text_color("indigo-600").hover_text_color("indigo-500")
                end
              end
            end
            
            # Submit Button
            div do
              button("Create account", type: "submit")
                .w_full
                .flex
                .justify_center
                .py(3)
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
                .transition
            end
          end
        end
        
        # Divider
        div.relative.mt(8) do
          div.absolute.inset(0).flex.items_center do
            div.w_full.border_t.border_color("gray-300")
          end
          div.relative.flex.justify_center.text_size("sm") do
            span("Already have an account?").px(2).bg("white").text_color("gray-500")
          end
        end
        
        # Sign in link
        div.mt(6) do
          link("Sign in instead", destination: "/login")
            .w_full
            .flex
            .justify_center
            .py(2)
            .px(4)
            .border
            .border_color("gray-300")
            .rounded("md")
            .shadow("sm")
            .text_size("sm")
            .font_weight("medium")
            .text_color("gray-700")
            .bg("white")
            .hover_bg("gray-50")
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
