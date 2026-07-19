# frozen_string_literal: true

module SwiftUIRails
  module Reactive
    # @State equivalent for component-local state
    module State
      extend ActiveSupport::Concern
      
      included do
        class_attribute :state_definitions, default: {}
        class_attribute :state_observers, default: {}
        
        # Override initialization instead of using hooks
        def initialize(...)
          super
          initialize_state_tracking if respond_to?(:initialize_state_tracking, true)
        end
      end
      
      class_methods do
        # Define a state variable
        # @state :count, 0
        # @state :user, -> { current_user }
        def state(name, initial_value = nil, type: nil, &block)
          name = name.to_sym
          initial = block || initial_value
          
          self.state_definitions = state_definitions.merge(
            name => {
              initial: initial,
              # Existing Ruby state declarations are dynamically typed. Callers
              # opt into Swift-like enforcement explicitly with `type:`.
              type: type
            }
          )
          
          # Define getter
          define_method(name) do
            @state_values ||= {}
            @state_values[name]
          end
          
          # Define setter that triggers reactivity
          define_method("#{name}=") do |value|
            @state_values ||= {}
            validate_state_value!(name, value)
            old_value = @state_values[name]
            @state_values[name] = value
            
            # Track state change for re-rendering
            track_state_change(name, old_value, value)
          end
          
          # Define mutation methods for arrays/hashes
          if initial.is_a?(Array)
            define_array_mutation_methods(name)
          elsif initial.is_a?(Hash)
            define_hash_mutation_methods(name)
          end
        end
        
        # Define a state observer
        def observe(state_name, &block)
          observers = Array(state_observers[state_name]).dup
          observers << block
          self.state_observers = state_observers.merge(state_name => observers)
        end
        
        private
        
        def infer_state_type(initial)
          case initial
          when Proc
            # Can't infer type from Proc
            nil
          when Integer
            Integer
          when String
            String
          when TrueClass, FalseClass
            :boolean
          when Array
            Array
          when Hash
            Hash
          else
            initial.class
          end
        end
        
        def define_array_mutation_methods(name)
          # Push method
          define_method("#{name}_push") do |*items|
            array = send(name).dup
            array.push(*items)
            send("#{name}=", array)
          end
          
          # Remove method
          define_method("#{name}_remove") do |item|
            array = send(name).dup
            array.delete(item)
            send("#{name}=", array)
          end
          
          # Clear method
          define_method("#{name}_clear") do
            send("#{name}=", [])
          end
        end
        
        def define_hash_mutation_methods(name)
          # Set key method
          define_method("#{name}_set") do |key, value|
            hash = send(name).dup
            hash[key] = value
            send("#{name}=", hash)
          end
          
          # Delete key method
          define_method("#{name}_delete") do |key|
            hash = send(name).dup
            hash.delete(key)
            send("#{name}=", hash)
          end
          
          # Clear method
          define_method("#{name}_clear") do
            send("#{name}=", {})
          end
        end
      end
      
      private

      def validate_state_value!(name, value)
        definition = self.class.state_definitions.fetch(name.to_sym)
        expected_type = definition[:type]
        return true if expected_type.nil?

        valid = if expected_type == :boolean
          value == true || value == false
        elsif expected_type.is_a?(Array)
          expected_type.any? { |candidate| value.is_a?(candidate) }
        else
          value.is_a?(expected_type)
        end
        return true if valid

        raise TypeError, "State '#{name}' must be a #{expected_type}"
      end
      
      def initialize_state_tracking
        @state_values ||= {}
        @state_changes ||= []
        @state_generation ||= SecureRandom.hex(8)
        
        # Initialize all state variables
        self.class.state_definitions.each do |name, definition|
          unless @state_values.key?(name)
            initial = definition[:initial]
            value = initial.is_a?(Proc) ? instance_exec(&initial) : initial
            @state_values[name] = value.respond_to?(:deep_dup) ? value.deep_dup : value
          end
        end

        capture_reactive_dependency_snapshot! if respond_to?(:capture_reactive_dependency_snapshot!, true)
      end
      
      def track_state_change(name, old_value, new_value)
        return if old_value == new_value
        
        @state_changes << {
          name: name,
          old_value: old_value,
          new_value: new_value,
          timestamp: Time.current.to_f
        }
        
        # Call observers
        if observers = self.class.state_observers[name]
          observers.each do |observer|
            instance_exec(new_value, old_value, &observer)
          end
        end

        request_automatic_rerender if respond_to?(:request_automatic_rerender, true)
      end
      
      def generate_state_updates
        return if @state_changes.empty?

        # Mark the rendered tree as stale without exposing old/new state
        # values in public HTML attributes. The encrypted snapshot remains the
        # only browser-carried representation of component-local state.
        @_content = @_content.to_s.gsub(
          /(<[^>]+)(>)/,
          "\\1 data-state-generation=\"#{ERB::Util.html_escape(@state_generation)}\" data-state-invalidated=\"true\"\\2"
        ).html_safe
      end
      
      # Helper to create reactive wrappers
      def reactive(&block)
        ReactiveContext.new(self, &block)
      end
      
      class ReactiveContext
        def initialize(component, &block)
          @component = component
          @block = block
        end
        
        def value
          @block.call
        end
        
        def on_change(&handler)
          # The server-owned reactive renderer consumes this callback.
          @change_handler = handler
          self
        end
      end
    end
  end
end
