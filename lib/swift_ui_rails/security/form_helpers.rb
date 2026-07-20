# frozen_string_literal: true

module SwiftUIRails
  module Security
    # SECURITY: Secure form helpers for CSRF protection
    module FormHelpers
      extend ActiveSupport::Concern
      
      included do
        # Ensure we have access to Rails form helpers
        if respond_to?(:helper_method)
          helper_method :render_csrf_protection, :csrf_meta_tags_dsl
        end
      end
      
      # SECURITY: Render CSRF protection token field
      # Uses Rails' built-in helpers to ensure proper CSRF protection
      def render_csrf_protection(action: nil, method: nil)
        return "" unless protect_against_forgery?

        # Bind the token to this form's action/method so apps with
        # per_form_csrf_tokens generate a correctly-scoped token.
        form_options = {}
        form_options[:action] = action if action
        form_options[:method] = method if method
        token = form_authenticity_token(form_options: form_options)
        param = request_forgery_protection_token
        
        # Return a hidden input element
        create_element(:input, nil,
          type: "hidden",
          name: param.to_s,
          value: token,
          autocomplete: "off"
        )
      end
      
      # SECURITY: Render CSRF meta tags for AJAX requests
      def csrf_meta_tags_dsl
        return [] unless protect_against_forgery?
        
        [
          create_element(:meta, nil,
            name: "csrf-param",
            content: request_forgery_protection_token.to_s
          ),
          create_element(:meta, nil,
            name: "csrf-token", 
            content: form_authenticity_token
          )
        ]
      end
      
      # SECURITY: Create a secure form with automatic CSRF protection
      def secure_form(action:, method: "POST", **attrs, &block)
        # Ensure method is uppercase
        method = method.to_s.upcase
        
        # Build form attributes
        attrs[:action] = action
        attrs[:method] = method == "GET" ? "GET" : "POST"
        attrs[:accept_charset] ||= "UTF-8"
        
        # Add data-turbo attributes if not disabled
        unless attrs.delete(:turbo) == false
          attrs[:data] ||= {}
          attrs[:data][:turbo] = "true" unless attrs[:data].key?(:turbo)
        end
        
        # Only bind the session CSRF token to same-origin submissions. A
        # cross-origin action would otherwise receive the token and could
        # replay it in a forged request against this app.
        same_origin_action = same_origin_action?(action)

        # Create the form element
        create_element(:form, nil, **attrs) do
          elements = []

          # Add CSRF token for non-GET, same-origin requests
          if method != "GET" && same_origin_action && protect_against_forgery?
            elements << render_csrf_protection(action: attrs[:action], method: method)
          end
          
          # Add method override for non-POST/GET methods
          if %w[PUT PATCH DELETE].include?(method)
            elements << create_element(:input, nil,
              type: "hidden",
              name: "_method",
              value: method.downcase,
              autocomplete: "off"
            )
          end
          
          # Add UTF-8 enforcer for older browsers
          elements << create_element(:input, nil,
            type: "hidden",
            name: "utf8",
            value: "✓",
            autocomplete: "off"
          )
          
          # Add the block content
          if block_given?
            block_content = instance_eval(&block)
            if block_content.is_a?(Array)
              elements.concat(block_content)
            else
              elements << block_content
            end
          end
          
          elements
        end
      end
      
      # SECURITY: Check if forgery protection is enabled
      def protect_against_forgery?
        return false unless defined?(ActionController::Base)

        # Rails exposes the global switch as a class attribute. Do not delegate
        # back through the view context here: DSLContext also includes this
        # module, and that round trip can recurse through method_missing.
        if ActionController::Base.respond_to?(:allow_forgery_protection)
          return !!ActionController::Base.allow_forgery_protection
        end

        configured = Rails.application.config.action_controller.allow_forgery_protection
        configured == true
      end
      
      # SECURITY: Get the CSRF token parameter name
      def request_forgery_protection_token
        if defined?(ActionController::Base)
          ActionController::Base.request_forgery_protection_token || :authenticity_token
        else
          :authenticity_token
        end
      end
      
      # SECURITY: Get the current CSRF token.
      #
      # In a real controller request the ActionView helper is always present
      # and returns a session-bound token the server accepts. The
      # non-helper branch is only reached by render-only contexts (storybook
      # previews, isolated DSL rendering) where no form is actually submitted,
      # so a placeholder keeps rendering working without ever affecting a real
      # submission. A missing session on a genuine request would already have
      # failed Rails' own forgery checks upstream.
      def form_authenticity_token(form_options: {})
        if respond_to?(:helpers) && helpers.respond_to?(:form_authenticity_token)
          helpers.form_authenticity_token(form_options: form_options)
        else
          # Render-only fallback: never reached during a real form submission.
          SecureRandom.base64(32)
        end
      end

      private

      # A form action is same-origin when it is host-less (relative). Anything
      # carrying a scheme or a network-path reference (//host) targets another
      # origin and must not receive the session CSRF token.
      def same_origin_action?(action)
        value = action.to_s
        return true if value.empty?

        !value.match?(%r{\A(?:[a-z][a-z0-9+.\-]*:)?//}i)
      end
    end
  end
end
