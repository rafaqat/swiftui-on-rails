# frozen_string_literal: true

module SwiftUIRails
  module Security
    # SECURITY: Validates component props to prevent security issues
    module ComponentValidator
      extend ActiveSupport::Concern
      
      # Common validation patterns
      VALID_VARIANTS = %w[primary secondary success danger warning info light dark].freeze
      VALID_SIZES = %w[xs sm md lg xl].freeze
      VALID_POSITIONS = %w[top bottom left right center].freeze
      VALID_ALIGNMENTS = %w[start center end stretch baseline].freeze
      
      included do
        # Add validation methods to components
        class_attribute :prop_validations, default: {}
      end
      
      # Validation methods
      module ClassMethods
        def register_prop_validation(name, validate: nil, enum: nil, pattern: nil, range: nil)
          validation = if enum
            { inclusion: { in: enum } }
          elsif pattern
            { format: { with: pattern } }
          elsif range
            { inclusion: { in: range } }
          elsif validate
            validation_for(validate)
          end

          self.prop_validations = prop_validations.merge(name => validation) if validation
        end

        # Define common prop validations
        def validates_variant(prop_name, allowed: VALID_VARIANTS)
          add_prop_validation(prop_name, {
            inclusion: { 
              in: allowed,
              message: "must be one of: #{allowed.join(', ')}"
            }
          })
        end
        
        def validates_size(prop_name, allowed: VALID_SIZES)
          add_prop_validation(prop_name, {
            inclusion: { 
              in: allowed,
              message: "must be one of: #{allowed.join(', ')}"
            }
          })
        end
        
        def validates_color(prop_name)
          add_prop_validation(prop_name, {
            format: { 
              with: /\A[a-zA-Z0-9\-]+\z/,
              message: "must be a valid color name"
            }
          })
        end
        
        def validates_number(prop_name, min: nil, max: nil)
          validations = {}
          validations[:numericality] = { greater_than_or_equal_to: min } if min
          validations[:numericality] ||= {}
          validations[:numericality][:less_than_or_equal_to] = max if max
          add_prop_validation(prop_name, validations)
        end

        def validates_inclusion(prop_name, allow_blank: false, message: nil, **options)
          validation_options = { in: options.fetch(:in), allow_blank: allow_blank }
          validation_options[:message] = message if message
          add_prop_validation(prop_name, { inclusion: validation_options })
        end
        
        def validates_url(prop_name, allow_blank: false)
          add_prop_validation(prop_name, {
            url: { allow_blank: allow_blank }
          })
        end
        
        def validates_email(prop_name, allow_blank: false)
          add_prop_validation(prop_name, {
            format: {
              with: URI::MailTo::EMAIL_REGEXP,
              message: "must be a valid email address",
              allow_blank: allow_blank
            }
          })
        end
        
        def validates_callable(prop_name, allow_nil: true)
          add_prop_validation(prop_name, {
            callable: { allow_nil: allow_nil }
          })
        end

        private

        def add_prop_validation(prop_name, validation)
          self.prop_validations = prop_validations.merge(prop_name => validation)
        end

        def validation_for(validation)
          case validation
          when :url
            { url: { allow_blank: false } }
          when :email
            { format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" } }
          when :callable
            { callable: { allow_nil: true } }
          when Proc
            { custom: { validator: validation } }
          when Hash
            validation
          else
            raise ArgumentError, "Unknown prop validation: #{validation.inspect}"
          end
        end
      end
      
      # Instance methods for validation
      def validate_props!
        return true if self.class.prop_validations.empty?
        
        errors = self.class.prop_validations.each_with_object([]) do |(prop_name, validations), error_list|
          value = send(prop_name)
          
          validations.each do |validation_type, options|
            case validation_type
            when :inclusion
              next if options[:allow_blank] && value.blank?

              # Convert both the value and the allowed list to strings for comparison
              unless options[:in].map(&:to_s).include?(value.to_s)
                error_list << "#{prop_name} #{options[:message] || 'is not included in the list'}"
              end
            when :format
              next if options[:allow_blank] && value.blank?

              unless value.to_s.match?(options[:with])
                error_list << "#{prop_name} #{options[:message] || 'is invalid'}"
              end
            when :numericality
              unless value.is_a?(Numeric) && value.real? &&
                     (!value.respond_to?(:finite?) || value.finite?)
                error_list << "#{prop_name} must be a finite number"
                next
              end

              if options[:greater_than_or_equal_to] && value < options[:greater_than_or_equal_to]
                error_list << "#{prop_name} must be greater than or equal to #{options[:greater_than_or_equal_to]}"
              end
              if options[:less_than_or_equal_to] && value > options[:less_than_or_equal_to]
                error_list << "#{prop_name} must be less than or equal to #{options[:less_than_or_equal_to]}"
              end
            when :url
              unless valid_url?(value, allow_blank: options[:allow_blank])
                error_list << "#{prop_name} must be a valid URL"
              end
            when :callable
              unless valid_callable?(value, allow_nil: options[:allow_nil])
                error_list << "#{prop_name} must be a callable (Proc or method)"
              end
            when :custom
              validator = options[:validator]
              unless instance_exec(value, &validator)
                error_list << "#{prop_name} is invalid"
              end
            end
          end
        end
        
        if errors.any?
          raise ArgumentError, "Component validation failed: #{errors.join(', ')}"
        end
        
        true
      end
      
      # Common validation helpers
      def valid_url?(url, allow_blank: false)
        return true if allow_blank && url.blank?
        return false if url.blank?

        !SwiftUIRails::Security::URLValidator.validate_url(url, allow_relative: true).nil?
      end
      
      def valid_callable?(value, allow_nil: true)
        return true if allow_nil && value.nil?
        value.respond_to?(:call)
      end
      
      # Sanitization helpers
      def sanitize_html(content)
        return "" if content.nil?
        
        # Use Rails' sanitize helper if available
        if respond_to?(:helpers) && helpers.respond_to?(:sanitize)
          helpers.sanitize(content)
        else
          # Basic HTML escaping
          ERB::Util.html_escape(content)
        end
      end
      
      def sanitize_css_class(class_name)
        return "" if class_name.nil?
        
        # Remove any non-alphanumeric characters except dash, underscore, and space
        class_name.to_s.gsub(/[^a-zA-Z0-9\-_ ]/, '')
      end
      
      def sanitize_id(id)
        return "" if id.nil?
        
        # IDs should start with letter and contain only alphanumeric, dash, underscore
        id = id.to_s.gsub(/[^a-zA-Z0-9\-_]/, '')
        id = "id-#{id}" unless id.match?(/^[a-zA-Z]/)
        id
      end
    end
  end
end
