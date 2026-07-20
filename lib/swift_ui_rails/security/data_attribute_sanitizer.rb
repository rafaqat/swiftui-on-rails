# frozen_string_literal: true

module SwiftUIRails
  module Security
    # SECURITY: Sanitizes data attributes to prevent XSS attacks
    module DataAttributeSanitizer
      extend ActiveSupport::Concern
      
      APPLICATION_JAVASCRIPT_KEYS = %w[action controller param target values].freeze
      APPLICATION_CALLBACK_PATTERN = /(?:\A|\s)[^\s]+->[a-zA-Z][a-zA-Z0-9_-]*#[a-zA-Z][a-zA-Z0-9_]*(?:\s|\z)/
      
      # List of potentially dangerous values that should be escaped
      DANGEROUS_PATTERNS = [
        /javascript:/i,
        /data:text\/html/i,
        /vbscript:/i,
        /onload=/i,
        /onerror=/i,
        /onclick=/i,
        /onmouse/i,
        /<script/i,
        /<iframe/i,
        /<object/i,
        /<embed/i,
        /document\./i,
        /window\./i,
        /eval\(/i,
        /setTimeout/i,
        /setInterval/i
      ].freeze

      class << self
        # SECURITY: Sanitize a single data attribute
        def sanitize_data_attribute(key, value)
          # Ensure key is safe
          safe_key = sanitize_data_key(key)
          reject_application_javascript!(key, value, safe_key)

          [safe_key, sanitize_value(value)]
        end
        
        # SECURITY: Sanitize a hash of data attributes
        def sanitize_data_attributes(attributes)
          return {} unless attributes.is_a?(Hash)
          
          sanitized = {}
          attributes.each do |key, value|
            safe_key, safe_value = sanitize_data_attribute(key, value)
            sanitized[safe_key] = safe_value
          end
          
          sanitized
        end
        
        # SECURITY: Create generic safe data attributes. Controller/action
        # options are rejected because application behavior belongs in Ruby.
        def safe_data_attributes(options = {})
          application_keys = options.keys.map(&:to_s) & APPLICATION_JAVASCRIPT_KEYS
          reject_application_options!(application_keys) if application_keys.any?

          attrs = {}
          
          # Generic data attributes
          if options[:data].is_a?(Hash)
            options[:data].each do |key, value|
              safe_key, safe_value = sanitize_data_attribute(key, value)
              attrs[safe_key] = safe_value
            end
          end
          
          attrs
        end
        
        private
        
        # Sanitize data attribute keys
        def sanitize_data_key(key)
          # Convert to string and dasherize
          key_str = key.to_s.dasherize
          
          # Remove data- prefix if present (we'll add it back)
          key_str = key_str.gsub(/^data-/, '')
          
          # Only allow alphanumeric, dash, and underscore
          key_str = key_str.gsub(/[^a-zA-Z0-9\-_]/, '')
          
          # Ensure it starts with a letter
          key_str = "x-#{key_str}" unless key_str.match?(/^[a-zA-Z]/)
          
          "data-#{key_str}"
        end
        
        # Sanitize data attribute values
        def sanitize_data_value(value)
          return "" if value.nil?
          
          # Convert to string
          value_str = value.to_s
          
          # Check for dangerous patterns
          DANGEROUS_PATTERNS.each do |pattern|
            if value_str.match?(pattern)
              # Log a sanitized, truncated preview: value_str is untrusted, so
              # interpolating it raw would allow CRLF log forging and dump
              # sensitive payloads. Prefer the pattern that matched.
              safe_preview = value_str.gsub(/[\r\n]+/, " ").truncate(120)
              Rails.logger.warn "Potential XSS attempt blocked in data attribute (pattern #{pattern.source}): #{safe_preview}"
              return ""
            end
          end
          
          # HTML escape the value
          ERB::Util.html_escape(value_str)
        end
        
        def reject_application_javascript!(key, value, safe_key)
          normalized = key.to_s.sub(/\Adata[-_]/, "").tr("-", "_")
          application_key = %w[action controller values].include?(normalized) ||
            (!normalized.start_with?("sui_") && normalized.match?(/(?:\A|_)(?:param|target|value)\z/))
          return unless application_key || value.to_s.match?(APPLICATION_CALLBACK_PATTERN)

          raise SwiftUIRails::SecurityError,
                "application JavaScript metadata `#{safe_key}` is unsupported; " \
                "declare a Ruby .on_tap/.on_change action or a finite semantic behavior"
        end

        def reject_application_options!(keys)
          raise SwiftUIRails::SecurityError,
                "application JavaScript options #{keys.sort.join(', ')} are unsupported; " \
                "declare Ruby actions or finite semantic behaviors"
        end
        
        # Sanitize generic values based on type
        def sanitize_value(value)
          case value
          when Integer, Float
            value.to_s
          when TrueClass, FalseClass
            value.to_s
          when Symbol
            value.to_s.gsub(/[^a-zA-Z0-9\-_]/, '')
          when String
            sanitize_data_value(value)
          when Array
            # Convert to JSON and escape
            ERB::Util.html_escape(value.to_json)
          when Hash
            # Convert to JSON and escape
            ERB::Util.html_escape(value.to_json)
          else
            # Unknown type - convert to string and escape
            ERB::Util.html_escape(value.to_s)
          end
        end
      end
    end
  end
end
