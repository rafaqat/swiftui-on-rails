# frozen_string_literal: true

module SwiftUIRails
  module Reactive
    # State debugging tools
    module Debugging
      extend ActiveSupport::Concern
      
      included do
        class_attribute :state_debugging_enabled, default: Rails.env.development?
        
        # Temporarily disabled to debug rendering issue
      end
      
      class_methods do
        # Enable/disable state debugging
        def debug_state(enabled = true)
          self.state_debugging_enabled = enabled
        end
      end
      
      # Public API for debugging
      def state_snapshot
        {
          component: {
            class: self.class.name,
            object_id: object_id,
            render_count: @render_count || 0
          },
          state: collect_state_values,
          bindings: collect_binding_values,
          observed: collect_observed_values,
          props: collect_prop_values,
          changes: @state_change_log || []
        }
      end
      
      def state_history
        @state_history || []
      end
      
      def log_state_change(category, name, old_value, new_value)
        return unless state_debugging_enabled
        
        @state_change_log ||= []
        @state_change_log << {
          category: category,
          name: name,
          old_value: old_value,
          new_value: new_value,
          timestamp: Time.current.to_f,
          backtrace: caller(2, 5) # Get 5 frames starting 2 levels up
        }
      end
      
      private
      
      def capture_initial_state
        @render_count = (@render_count || 0) + 1
        @state_before_render = state_snapshot
        
        # Keep history of last 10 renders
        @state_history ||= []
        @state_history << @state_before_render
        @state_history = @state_history.last(10)
      end
      
      def add_debug_info
        return unless state_debugging_enabled
        
        debug_panel = generate_debug_panel
        @_content = (@_content.to_s + debug_panel).html_safe
      end
      
      def generate_debug_panel
        state_data = state_snapshot

        <<~HTML
          <details class="swift-ui-debug-panel">
            <summary class="swift-ui-debug-trigger" title="Inspect Component State">
              🔍 #{ERB::Util.html_escape(self.class.name)} State Inspector
            </summary>
            <div class="debug-header">
              <h4>#{ERB::Util.html_escape(self.class.name)} State Inspector</h4>
            </div>
            <div class="debug-content">
              #{generate_debug_sections(state_data)}
            </div>
          </details>
          #{debug_styles}
        HTML
      end
      
      def generate_debug_sections(state_data)
        sections = []
        
        # Component info
        sections << debug_section("Component", state_data[:component])
        
        # Props
        if state_data[:props].any?
          sections << debug_section("Props", state_data[:props])
        end
        
        # State values
        if state_data[:state].any?
          sections << debug_section("@State", state_data[:state])
        end
        
        # Bindings
        if state_data[:bindings].any?
          sections << debug_section("@Binding", state_data[:bindings])
        end
        
        # Observed objects
        if state_data[:observed].any?
          sections << debug_section("@ObservedObject", state_data[:observed])
        end
        
        # Recent changes
        if state_data[:changes].any?
          sections << debug_changes_section(state_data[:changes].last(5))
        end
        
        sections.join("\n")
      end
      
      def debug_section(title, data)
        <<~HTML
          <div class="debug-section">
            <h5>#{title}</h5>
            <table class="debug-table">
              #{data.map { |k, v| debug_row(k, v) }.join("\n")}
            </table>
          </div>
        HTML
      end
      
      def debug_row(key, value)
        formatted_value = format_debug_value(value)
        value_class = ERB::Util.html_escape(value.class.name.downcase)

        <<~HTML
          <tr>
            <td class="debug-key">#{ERB::Util.html_escape(key)}</td>
            <td class="debug-value #{value_class}">#{formatted_value}</td>
          </tr>
        HTML
      end
      
      def debug_changes_section(changes)
        <<~HTML
          <div class="debug-section">
            <h5>Recent Changes</h5>
            <div class="debug-changes">
              #{changes.map { |change| debug_change_entry(change) }.join("\n")}
            </div>
          </div>
        HTML
      end
      
      def debug_change_entry(change)
        time_ago = Time.current - Time.at(change[:timestamp])
        
        <<~HTML
          <div class="debug-change">
            <div class="change-header">
              <span class="change-name">#{ERB::Util.html_escape("#{change[:category]}.#{change[:name]}")}</span>
              <span class="change-time">#{time_ago.round}s ago</span>
            </div>
            <div class="change-values">
              <span class="old-value">#{format_debug_value(change[:old_value])}</span>
              →
              <span class="new-value">#{format_debug_value(change[:new_value])}</span>
            </div>
          </div>
        HTML
      end
      
      def format_debug_value(value)
        case value
        when nil
          '<em>nil</em>'
        when String
          %("#{ERB::Util.html_escape(value)}")
        when Symbol
          ":#{ERB::Util.html_escape(value.to_s)}"
        when TrueClass, FalseClass
          value.to_s
        when Numeric
          value.to_s
        when Array
          "[#{value.size} items]"
        when Hash
          "{#{value.size} keys}"
        else
          "#{value.class.name}##{value.object_id}"
        end
      end
      
      def collect_state_values
        return {} unless self.class.respond_to?(:state_definitions)
        
        self.class.state_definitions.keys.each_with_object({}) do |name, hash|
          hash[name] = send(name) if respond_to?(name)
        end
      end
      
      def collect_binding_values
        return {} unless self.class.respond_to?(:binding_definitions)
        
        self.class.binding_definitions.keys.each_with_object({}) do |name, hash|
          hash[name] = send("#{name}_value") if respond_to?("#{name}_value")
        end
      end
      
      def collect_observed_values
        return {} unless self.class.respond_to?(:observed_object_definitions)
        
        self.class.observed_object_definitions.keys.each_with_object({}) do |name, hash|
          hash[name] = send("#{name}_data") if respond_to?("#{name}_data")
        end
      end
      
      def collect_prop_values
        prop_definitions = if self.class.respond_to?(:swift_props)
          self.class.swift_props
        elsif self.class.respond_to?(:prop_definitions)
          self.class.prop_definitions
        else
          {}
        end

        prop_definitions.keys.each_with_object({}) do |name, hash|
          hash[name] = instance_variable_get("@#{name}")
        end
      end
      
      def debug_styles
        <<~CSS
          <style>
            .swift-ui-debug-trigger {
              position: fixed;
              bottom: 20px;
              right: 20px;
              display: inline-flex;
              align-items: center;
              gap: 6px;
              max-width: 90vw;
              padding: 8px 14px;
              border-radius: 999px;
              background: #3b82f6;
              color: white;
              border: none;
              font-size: 13px;
              font-weight: 600;
              white-space: nowrap;
              overflow: hidden;
              text-overflow: ellipsis;
              cursor: pointer;
              box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
              z-index: 9990;
              transition: transform 0.2s;
            }
            
            .swift-ui-debug-trigger:hover {
              transform: scale(1.1);
            }
            
            .swift-ui-debug-panel {
              position: fixed;
              bottom: 80px;
              right: 20px;
              width: 400px;
              max-height: 600px;
              background: white;
              border: 1px solid #e5e7eb;
              border-radius: 8px;
              box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
              z-index: 9991;
              overflow: hidden;
              display: flex;
              flex-direction: column;
            }
            
            .swift-ui-debug-panel.open {
              display: flex !important;
            }
            
            .debug-header {
              background: #1f2937;
              color: white;
              padding: 12px 16px;
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            
            .debug-header h4 {
              margin: 0;
              font-size: 14px;
              font-weight: 600;
            }
            
            .debug-header button {
              background: none;
              border: none;
              color: white;
              font-size: 20px;
              cursor: pointer;
              padding: 0;
              width: 24px;
              height: 24px;
            }
            
            .debug-content {
              flex: 1;
              overflow-y: auto;
              padding: 16px;
            }
            
            .debug-section {
              margin-bottom: 20px;
            }
            
            .debug-section h5 {
              margin: 0 0 8px 0;
              font-size: 12px;
              font-weight: 600;
              text-transform: uppercase;
              color: #6b7280;
              letter-spacing: 0.05em;
            }
            
            .debug-table {
              width: 100%;
              font-size: 13px;
            }
            
            .debug-table tr {
              border-bottom: 1px solid #f3f4f6;
            }
            
            .debug-table tr:last-child {
              border-bottom: none;
            }
            
            .debug-key {
              padding: 8px 12px 8px 0;
              font-weight: 600;
              color: #374151;
              vertical-align: top;
            }
            
            .debug-value {
              padding: 8px 0;
              color: #111827;
              word-break: break-word;
            }
            
            .debug-value.string {
              color: #059669;
            }
            
            .debug-value.number,
            .debug-value.integer,
            .debug-value.float {
              color: #3b82f6;
            }
            
            .debug-value.trueclass,
            .debug-value.falseclass {
              color: #8b5cf6;
            }
            
            .debug-value em {
              color: #6b7280;
              font-style: normal;
            }
            
            .debug-changes {
              font-size: 12px;
            }
            
            .debug-change {
              padding: 8px;
              background: #f9fafb;
              border-radius: 4px;
              margin-bottom: 8px;
            }
            
            .debug-change:last-child {
              margin-bottom: 0;
            }
            
            .change-header {
              display: flex;
              justify-content: space-between;
              margin-bottom: 4px;
            }
            
            .change-name {
              font-weight: 600;
              color: #374151;
            }
            
            .change-time {
              color: #6b7280;
              font-size: 11px;
            }
            
            .change-values {
              color: #6b7280;
            }
            
            .old-value {
              color: #ef4444;
            }
            
            .new-value {
              color: #10b981;
            }
          </style>
        CSS
      end
    end
  end
end
