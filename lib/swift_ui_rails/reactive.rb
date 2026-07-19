# frozen_string_literal: true

require_relative "reactive/state"
require_relative "reactive/binding"
require_relative "reactive/observed_object"
require_relative "reactive/rendering"
require_relative "reactive/component_actions_controller"
require_relative "reactive/debugging"

module SwiftUIRails
  # SwiftUI-style reactive state management
  module Reactive
    extend ActiveSupport::Concern
    
    included do
      # Include all reactive modules
      include State
      include Binding
      include ObservedObject
      include Rendering
      include Debugging if Rails.env.development?
    end
    
    class_methods do
      # Configure reactive features
      def reactive_config
        @reactive_config ||= {
          auto_render: true,
          debug: Rails.env.development?,
          cable_enabled: true,
          debounce_ms: 100
        }
      end
      
      def configure_reactive
        yield reactive_config
      end
    end
    
    # Helper methods for reactive components
    def reactive?
      true
    end
    
    def state_dependencies
      declared = []
      declared.concat(self.class.state_definitions.keys.map { |name| "state.#{name}" })
      declared.concat(self.class.binding_definitions.keys.map { |name| "binding.#{name}" })

      observed = self.class.observed_object_definitions.each_with_object([]) do |(name, _definition), dependencies|
        keys = send(name).data.keys
        dependencies.concat(keys.map { |key| "observed.#{name}.#{key}" })
      end

      baseline = (@reactive_dependency_snapshot || {}).keys
      (declared + observed + baseline).uniq
    end
    
    # Trigger manual update
    def trigger_update
      return unless reactive?
      
      if defined?(Reactive::ReactiveUpdateJob)
        Reactive::ReactiveUpdateJob.perform_later(
          self.class.name,
          "swift-ui-#{self.class.name.underscore.dasherize}-#{object_id}",
          serialize_props
        )
      end
    end
    
    # Check if component should update
    def should_update?(new_props = {})
      # Always update if props changed
      return true if props_changed?(new_props)
      
      # Check if any reactive state changed
      state_dependencies.any? { |dep| dependency_changed?(dep) }
    end

    # A namespaced, immutable-at-the-boundary snapshot used by both update
    # invalidation and server fingerprints. Namespacing prevents a state,
    # binding, and observed key with the same name from overwriting each other.
    def reactive_state_snapshot
      {
        props: respond_to?(:serialize_props, true) ? send(:serialize_props) : {},
        state: self.class.state_definitions.each_key.to_h { |name| [name, send(name)] },
        bindings: self.class.binding_definitions.each_key.to_h { |name| [name, send("#{name}_value")] },
        observed: self.class.observed_object_definitions.each_key.to_h { |name| [name, send(name).data] }
      }.deep_dup
    end

    # Marks the current values as consumed by a successful render. Subsequent
    # in-place collection mutations are still detected because the baseline is
    # a deep copy rather than a reference to component state.
    def capture_reactive_dependency_snapshot!
      @reactive_dependency_snapshot = current_reactive_dependency_values.deep_dup
      @state_changes = [] if defined?(@state_changes)
      @binding_changes = [] if defined?(@binding_changes)
      @observed_changes = {} if defined?(@observed_changes)
      @needs_rerender = false
      @reactive_dependency_snapshot
    end

    def request_automatic_rerender
      @needs_rerender = true
    end

    def needs_rerender?
      @needs_rerender == true
    end
    
    private
    
    def props_changed?(new_props)
      return false if new_props.empty?

      prop_definitions = if self.class.respond_to?(:swift_props)
        self.class.swift_props
      elsif self.class.respond_to?(:prop_definitions)
        self.class.prop_definitions
      else
        {}
      end

      prop_definitions.keys.any? do |prop_name|
        new_value = if new_props.key?(prop_name)
          new_props[prop_name]
        elsif new_props.key?(prop_name.to_s)
          new_props[prop_name.to_s]
        else
          next false
        end
        current_value = instance_variable_get("@#{prop_name}")
        new_value != current_value
      end
    end
    
    def dependency_changed?(dependency)
      dependency = dependency.to_s
      return true if pending_reactive_dependencies.include?(dependency)

      baseline = @reactive_dependency_snapshot || {}
      current = current_reactive_dependency_values
      baseline.key?(dependency) != current.key?(dependency) || baseline[dependency] != current[dependency]
    end

    def current_reactive_dependency_values
      values = {}

      self.class.state_definitions.each_key do |name|
        values["state.#{name}"] = send(name)
      end
      self.class.binding_definitions.each_key do |name|
        values["binding.#{name}"] = send("#{name}_value")
      end
      self.class.observed_object_definitions.each_key do |name|
        send(name).data.each do |key, value|
          values["observed.#{name}.#{key}"] = value
        end
      end

      values
    end

    def pending_reactive_dependencies
      dependencies = []
      dependencies.concat(Array(@state_changes).map { |change| "state.#{change[:name]}" })
      dependencies.concat(Array(@binding_changes).map { |change| "binding.#{change[:name]}" })

      (@observed_changes || {}).each do |store_name, changes|
        changes.each_key do |key|
          dependencies << "observed.#{store_name}.#{key}"
        end
      end

      dependencies.uniq
    end
  end
end
