# frozen_string_literal: true

module SwiftUIRails
  module Reactive
    # @Binding equivalent for two-way data flow
    module Binding
      extend ActiveSupport::Concern
      
      included do
        class_attribute :binding_definitions, default: {}
      end
      
      class_methods do
        # Define a binding property
        # @binding :is_selected
        # @binding :text_value, type: String
        def binding(name, type: nil, default: nil)
          self.binding_definitions = binding_definitions.merge(
            name => {
              type: type,
              default: default
            }
          )
          
          # Define getter that returns a Binding object
          define_method(name) do
            @bindings ||= {}
            definition = self.class.binding_definitions.fetch(name)
            @bindings[name] ||= BindingValue.new(
              getter: -> { get_binding_value(name) },
              setter: ->(value) { set_binding_value(name, value) },
              source: self,
              name: name,
              type: definition[:type]
            )
          end
          
          # Define setter for direct assignment
          define_method("#{name}=") do |value|
            set_binding_value(name, value)
          end
          
          # Define raw value getter
          define_method("#{name}_value") do
            get_binding_value(name)
          end
        end
      end

      # Snapshot only declared root bindings. Derived projections are views of
      # these values and therefore do not need an independent lifecycle.
      def binding_values
        self.class.binding_definitions.each_key.to_h do |name|
          value = send("#{name}_value")
          [name, value.respond_to?(:deep_dup) ? value.deep_dup : value]
        end
      end

      def binding_values=(values)
        raise TypeError, "binding values must be a Hash" unless values.is_a?(Hash)

        values.to_h.symbolize_keys.slice(*self.class.binding_definitions.keys).each do |name, value|
          definition = self.class.binding_definitions.fetch(name)
          validate_binding_type!(name, value, definition[:type])
          if instance_variable_defined?("@#{name}")
            instance_variable_set("@#{name}", value.respond_to?(:deep_dup) ? value.deep_dup : value)
          else
            @binding_values ||= {}
            @binding_values[name] = value.respond_to?(:deep_dup) ? value.deep_dup : value
          end
        end
      end
      
      private
      
      def get_binding_value(name)
        # Check if value was passed as prop
        if instance_variable_defined?("@#{name}")
          instance_variable_get("@#{name}")
        elsif @binding_values&.key?(name)
          @binding_values[name]
        else
          default = self.class.binding_definitions.fetch(name)[:default]
          value = default.respond_to?(:call) ? instance_exec(&default) : default
          @binding_values ||= {}
          @binding_values[name] = value.respond_to?(:deep_dup) ? value.deep_dup : value
        end
      end
      
      def set_binding_value(name, value)
        definition = self.class.binding_definitions.fetch(name)
        validate_binding_type!(name, value, definition[:type])

        @binding_values ||= {}
        old_value = get_binding_value(name)
        if instance_variable_defined?("@#{name}")
          instance_variable_set("@#{name}", value)
        else
          @binding_values[name] = value
        end
        
        # Notify parent component if this is a child binding
        @parent_binding_callbacks&.fetch(name, nil)&.call(name, value, old_value)
        
        # Track change for reactivity
        track_binding_change(name, old_value, value)
      end

      def validate_binding_type!(name, value, allowed_type)
        type_matches = if allowed_type.is_a?(Array)
          allowed_type.any? { |type| value.is_a?(type) }
        else
          allowed_type.nil? || value.is_a?(allowed_type)
        end
        return true if type_matches

        raise TypeError, "Binding '#{name}' must be a #{allowed_type}"
      end
      
      def track_binding_change(name, old_value, new_value)
        return if old_value == new_value
        
        @binding_changes ||= []
        @binding_changes << {
          name: name,
          old_value: old_value,
          new_value: new_value,
          timestamp: Time.current.to_f
        }

        request_automatic_rerender if respond_to?(:request_automatic_rerender, true)
      end
      
      # Pass binding to child component
      def pass_binding(component, binding_name, as: nil)
        target_name = as || binding_name
        
        # Set up two-way connection
        component.instance_variable_set("@#{target_name}", send(binding_name).value)
        callbacks = component.instance_variable_get("@parent_binding_callbacks") || {}
        callbacks[target_name] = ->(name, value, old_value) do
            if name == target_name
              send(binding_name).value = value
            end
          end
        component.instance_variable_set("@parent_binding_callbacks", callbacks)
      end
    end
    
    # Binding value wrapper
    class BindingValue
      attr_reader :source, :name

      WIRE_TYPE_NAMES = {
        Integer => "integer",
        Float => "float",
        String => "string",
        TrueClass => "boolean",
        FalseClass => "boolean"
      }.freeze
      
      def initialize(getter:, setter:, source:, name:, type: nil, transportable: true)
        @getter = getter
        @setter = setter
        @source = source
        @name = name
        @type = type
        @transportable = transportable
      end
      
      def value
        @getter.call
      end
      
      def value=(new_value)
        old_value = value
        @setter.call(new_value)
        @change_handler&.call(new_value, old_value) if old_value != new_value
      end
      
      # Allow binding to be used in DSL
      def to_s
        value.to_s
      end
      
      # For reactive updates
      def on_change(&block)
        @change_handler = block
        self
      end

      # Explicit metadata for DSL form controls. Keeping this opt-in avoids
      # surprising attributes on values used only for display while still
      # giving controls a complete no-JavaScript name/value fallback.
      #
      #   textfield(**query.input_attributes(placeholder: "Search"))
      #   input(**enabled.checkbox_attributes)
      def metadata(**attributes)
        ensure_transportable!
        custom_data = attributes.delete(:data) || {}

        {
          name: name.to_s,
          data: custom_data.merge(
            sui_binding: name.to_s,
            sui_binding_type: wire_type
          )
        }.merge(attributes)
      end

      def input_attributes(**attributes)
        metadata(**attributes).reverse_merge(value: value)
      end

      def checkbox_attributes(**attributes)
        metadata(**attributes).reverse_merge(value: "1", checked: !!value)
      end

      def select_attributes(**attributes)
        metadata(**attributes).reverse_merge(selected: value)
      end
      
      # Create derived binding
      def map(&transform)
        BindingValue.new(
          getter: -> { transform.call(value) },
          setter: ->(new_value) { 
            # Reverse transform if possible
            if transform.respond_to?(:inverse)
              self.value = transform.inverse.call(new_value)
            end
          },
          source: source,
          name: "#{name}_mapped",
          transportable: false
        )
      end
      
      # Create binding projection (for nested values)
      def project(key_path)
        keys = key_path.to_s.split('.')
        
        BindingValue.new(
          getter: -> { 
            keys.reduce(value) { |obj, key| read_projection_value(obj, key) }
          },
          setter: ->(new_value) {
            obj = duplicate_projection_value(value)
            parent_keys = keys[0...-1]
            last_key = keys.last
            parent = parent_keys.reduce(obj) { |current, key| read_projection_value(current, key) }
            raise KeyError, "Cannot project #{key_path.inspect}" if parent.nil? || last_key.nil?
            
            if parent.respond_to?("#{last_key}=")
              parent.public_send("#{last_key}=", new_value)
            elsif parent.respond_to?(:[]=)
              projection_key = projection_key_for(parent, last_key)
              parent[projection_key] = new_value
            else
              raise TypeError, "Projected value does not support assignment"
            end
            
            self.value = obj
          },
          source: source,
          name: "#{name}.#{key_path}",
          transportable: false
        )
      end

      private

      def ensure_transportable!
        return if @transportable

        raise ArgumentError, "Derived bindings cannot be sent as a root component binding"
      end

      def wire_type
        types = Array(@type)
        return "boolean" if types.any? { |type| type == TrueClass || type == FalseClass }

        WIRE_TYPE_NAMES.fetch(types.first) do
          WIRE_TYPE_NAMES.fetch(value.class, "string")
        end
      end

      def read_projection_value(object, key)
        return nil if object.nil?

        if object.respond_to?(:key?)
          return object[key] if object.key?(key)

          symbol_key = key.to_sym
          return object[symbol_key] if object.key?(symbol_key)
        end

        return object.public_send(key) if object.respond_to?(key)
        return object[key] if object.respond_to?(:[])

        nil
      end

      def projection_key_for(object, key)
        return key unless object.respond_to?(:key?)
        return key if object.key?(key)

        symbol_key = key.to_sym
        object.key?(symbol_key) ? symbol_key : key
      end

      def duplicate_projection_value(value)
        value.respond_to?(:deep_dup) ? value.deep_dup : value.dup
      end
    end
  end
end
