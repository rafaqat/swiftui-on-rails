# frozen_string_literal: true

class AuthFormComponent < SwiftUIRails::Component::Base
  include SwiftUIRails::Security::FormHelpers
  prop :mode, type: Symbol, default: :login # :login or :register
  prop :action_path, type: String, default: nil
  prop :logo_url, type: String, default: ENV.fetch("DEFAULT_LOGO_URL", "/assets/logo.svg")
  prop :company_name, type: String, default: "Your Company"
  prop :csrf_token, type: String, default: nil
  
  # Login specific props
  prop :forgot_password_path, type: String, default: "#"
  prop :signup_path, type: String, default: "/register"
  
  # Register specific props
  prop :login_path, type: String, default: "/login"
  prop :terms_path, type: String, default: "/terms"
  prop :privacy_path, type: String, default: "/privacy"
  prop :require_name, type: [TrueClass, FalseClass], default: true
  
  # Form field props for pre-filling
  prop :email_value, type: String, default: ""
  prop :first_name_value, type: String, default: ""
  prop :last_name_value, type: String, default: ""
  
  # Error handling
  prop :errors, type: Hash, default: {}
  prop :flash_message, type: String, default: nil
  prop :flash_type, type: Symbol, default: :notice # :notice, :alert, :error
  
  swift_ui do
    div.flex.tw("min-h-full").tw("flex-col").justify_center.px(6).py(12).tw("lg:px-8") do
      # Logo and title section
      div.tw("sm:mx-auto sm:w-full sm:max-w-sm") do
        div.tw("mx-auto h-10 w-10") do
          image(src: logo_url, alt: company_name).tw("w-full h-full")
        end
        
        div.mt(10).text_center do
          text(mode == :login ? "Sign in to your account" : "Create your account")
            .text_size("2xl")
            .tw("leading-9")
            .font_weight("bold")
            .tw("tracking-tight")
            .text_color("gray-900")
        end
      end
      
      # Flash message
      if flash_message
        div.mt(4).tw("sm:mx-auto sm:w-full sm:max-w-sm") do
          div.rounded("md").p(4).tw(flash_alert_classes) do
            text(flash_message)
          end
        end
      end
      
      # Form section
      div.mt(10).tw("sm:mx-auto sm:w-full sm:max-w-sm") do
        secure_form(
          action: action_path || (mode == :login ? "/login" : "/register"), 
          method: "POST"
        ).tw("space-y-6") do
          
          # Name fields for registration
          if mode == :register && require_name
            div do
              # First name
              div do
                label(for: "first_name").block.text_size("sm").tw("leading-6").font_weight("medium").text_color("gray-900") do
                  text("First name")
                end
                div.mt(2) do
                  input(
                    type: "text",
                    name: "first_name",
                    id: "first_name",
                    value: first_name_value,
                    autocomplete: "given-name",
                    required: true
                  ).block.w_full.rounded("md").bg("white").px(3).py(1.5)
                   .text_size("base").text_color("gray-900")
                   .tw(input_border_classes(:first_name))
                   .tw("placeholder:text-gray-400")
                   .tw("focus:outline focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600")
                   .tw("sm:text-sm sm:leading-6")
                end
                if errors[:first_name].present?
                  div do
                    text(errors[:first_name].is_a?(Array) ? errors[:first_name].first : errors[:first_name])
                  end.mt(2).text_size("sm").text_color("red-600")
                end
              end
              
              # Last name
              div do
                label(for: "last_name").block.text_size("sm").tw("leading-6").font_weight("medium").text_color("gray-900") do
                  text("Last name")
                end
                div.mt(2) do
                  input(
                    type: "text",
                    name: "last_name",
                    id: "last_name",
                    value: last_name_value,
                    autocomplete: "family-name",
                    required: true
                  ).block.w_full.rounded("md").bg("white").px(3).py(1.5)
                   .text_size("base").text_color("gray-900")
                   .tw(input_border_classes(:last_name))
                   .tw("placeholder:text-gray-400")
                   .tw("focus:outline focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600")
                   .tw("sm:text-sm sm:leading-6")
                end
                if errors[:last_name].present?
                  div do
                    text(errors[:last_name].is_a?(Array) ? errors[:last_name].first : errors[:last_name])
                  end.mt(2).text_size("sm").text_color("red-600")
                end
              end
            end.tw("grid grid-cols-2 gap-4")
          end
          
          # Email field
          div do
            label(for: "email").block.text_size("sm").tw("leading-6").font_weight("medium").text_color("gray-900") do
              text("Email address")
            end
            div.mt(2) do
              input(
                type: "email",
                name: "email",
                id: "email",
                value: email_value,
                autocomplete: "email",
                required: true
              ).block.w_full.rounded("md").bg("white").px(3).py(1.5)
               .text_size("base").text_color("gray-900")
               .tw(input_border_classes(:email))
               .tw("placeholder:text-gray-400")
               .tw("focus:outline focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600")
               .tw("sm:text-sm sm:leading-6")
            end
            if errors[:email].present?
              div do
                text(errors[:email].is_a?(Array) ? errors[:email].first : errors[:email])
              end.mt(2).text_size("sm").text_color("red-600")
            end
          end
          
          # Password fields
          div do
            div.flex.items_center.justify_between do
              label(for: "password").block.text_size("sm").tw("leading-6").font_weight("medium").text_color("gray-900") do
                text("Password")
              end
              if mode == :login
                div.text_size("sm") do
                  link("Forgot password?", destination: forgot_password_path)
                    .font_weight("semibold")
                    .text_color("indigo-600")
                    .hover("text-indigo-500")
                end
              end
            end
            div.mt(2) do
              input(
                type: "password",
                name: "password",
                id: "password",
                autocomplete: mode == :login ? "current-password" : "new-password",
                required: true
              ).block.w_full.rounded("md").bg("white").px(3).py(1.5)
               .text_size("base").text_color("gray-900")
               .tw(input_border_classes(:password))
               .tw("placeholder:text-gray-400")
               .tw("focus:outline focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600")
               .tw("sm:text-sm sm:leading-6")
            end
            if errors[:password].present?
              div do
                text(errors[:password].is_a?(Array) ? errors[:password].first : errors[:password])
              end.mt(2).text_size("sm").text_color("red-600")
            end
          end
          
          # Password confirmation for registration
          if mode == :register
            div do
              label(for: "password_confirmation").block.text_size("sm").tw("leading-6").font_weight("medium").text_color("gray-900") do
                text("Confirm password")
              end
              div.mt(2) do
                input(
                  type: "password",
                  name: "password_confirmation",
                  id: "password_confirmation",
                  autocomplete: "new-password",
                  required: true
                ).block.w_full.rounded("md").bg("white").px(3).py(1.5)
                 .text_size("base").text_color("gray-900")
                 .tw(input_border_classes(:password_confirmation))
                 .tw("placeholder:text-gray-400")
                 .tw("focus:outline focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600")
                 .tw("sm:text-sm sm:leading-6")
              end
              if errors[:password_confirmation].present?
                div do
                  text(errors[:password_confirmation].is_a?(Array) ? errors[:password_confirmation].first : errors[:password_confirmation])
                end.mt(2).text_size("sm").text_color("red-600")
              end
            end
          end
          
          # Terms checkbox for registration
          if mode == :register
            div.flex.items_start do
              div.flex.items_center.h(5) do
                input(
                  type: "checkbox",
                  name: "agree_terms",
                  id: "agree_terms",
                  required: true
                ).h(4).w(4).rounded.border_color("gray-300").text_color("indigo-600")
                 .tw("focus:ring-indigo-500")
              end
              div.ml(3).text_size("sm") do
                label(for: "agree_terms").text_color("gray-600") do
                  text("I agree to the ")
                  link("Terms", destination: terms_path)
                    .font_weight("medium")
                    .text_color("indigo-600")
                    .hover("text-indigo-500")
                  text(" and ")
                  link("Privacy Policy", destination: privacy_path)
                    .font_weight("medium")
                    .text_color("indigo-600")
                    .hover("text-indigo-500")
                end
              end
            end
            if errors[:agree_terms].present?
              div do
                text(errors[:agree_terms].is_a?(Array) ? errors[:agree_terms].first : errors[:agree_terms])
              end.mt(2).text_size("sm").text_color("red-600")
            end
          end
          
          # Submit button
          div do
            button(
              mode == :login ? "Sign in" : "Create account", 
              type: "submit"
            ).flex.w_full.justify_center
             .rounded("md")
             .bg("indigo-600")
             .px(3).py(1.5)
             .text_size("sm").tw("leading-6")
             .font_weight("semibold")
             .text_color("white")
             .shadow("xs")
             .hover("bg-indigo-500")
             .tw("focus-visible:outline focus-visible:outline-2")
             .tw("focus-visible:outline-offset-2")
             .tw("focus-visible:outline-indigo-600")
          end
        end
        
        # Bottom link
        div do
          if mode == :login
            text("Not a member? ")
            link("Start a 14 day free trial", destination: signup_path)
              .font_weight("semibold")
              .text_color("indigo-600")
              .hover("text-indigo-500")
          else
            text("Already have an account? ")
            link("Sign in", destination: login_path)
              .font_weight("semibold")
              .text_color("indigo-600")
              .hover("text-indigo-500")
          end
        end.mt(10).text_center.text_size("sm").tw("leading-6").text_color("gray-500")
      end
    end
  end
  
  private
  
  def input_border_classes(field)
    if errors[field].present?
      "outline outline-1 -outline-offset-1 outline-red-300"
    else
      "outline outline-1 -outline-offset-1 outline-gray-300"
    end
  end
  
  def flash_alert_classes
    case flash_type
    when :error, :alert
      "bg-red-50 text-red-800 border border-red-200"
    when :success
      "bg-green-50 text-green-800 border border-green-200"
    else
      "bg-blue-50 text-blue-800 border border-blue-200"
    end
  end
end