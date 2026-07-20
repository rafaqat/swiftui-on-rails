# frozen_string_literal: true

module SwiftUIRails
  module Reactive
    # @ObservedObject equivalent for shared state management
    module ObservedObject
      extend ActiveSupport::Concern

      included do
        class_attribute :observed_object_definitions, default: {}

        # Rendering needs the stream actually used by each store, not merely
        # the property name chosen by the component author. In particular, a
        # callable store can select its stream at instance creation time and
        # an explicit ObservableStore may have an id unrelated to the
        # declaration name. Defining this on the host class intentionally
        # takes precedence over Rendering's compatibility fallback.
        define_method(:observed_store_names) do
          self.class.observed_object_definitions.map do |name, definition|
            store = send(name)
            stream_id = if store.respond_to?(:id) && store.id.present?
              store.id
            else
              definition[:stream] || name
            end

            ObservableStore.normalize_stream_id(stream_id)
          end.uniq
        end
        private :observed_store_names
      end
      
      class_methods do
        # Define an observed object property
        # @observed_object :user_store
        # @observed_object :app_state, type: AppState
        def observed_object(name, type: nil, store: nil, stream: nil)
          name = name.to_sym
          self.observed_object_definitions = observed_object_definitions.merge(
            name => {
              type: type,
              store: store || name,
              stream: stream || name
            }
          )
          
          # Define getter that returns the observed store
          define_method(name) do
            @observed_objects ||= {}
            @observed_objects[name] ||= begin
              definition = self.class.observed_object_definitions.fetch(name)
              store_reference = definition[:store]
              candidate = if store_reference.respond_to?(:call)
                instance_exec(&store_reference)
              elsif store_reference.respond_to?(:subscribe) && store_reference.respond_to?(:data)
                store_reference
              else
                ObservableStore.find_or_create(store_reference)
              end

              if definition[:type] && !candidate.is_a?(definition[:type])
                raise TypeError, "Observed object '#{name}' must be a #{definition[:type]}"
              end

              candidate
            end
          end
          
          # Define convenience methods for accessing store data
          define_method("#{name}_data") do
            send(name).data
          end
          
          # Define method to update store
          define_method("update_#{name}") do |&block|
            send(name).update(&block)
          end
        end

        # Production-oriented observation for data whose authority lives in a
        # database, cache, or service rather than this process. The loader runs
        # once for each component render; application callbacks call
        # ObservableStore.invalidate(stream) after committing a change.
        def observed_resource(name, stream: name, &loader)
          raise ArgumentError, "observed_resource requires a loader block" unless loader

          observed_object(
            name,
            type: ObservedResource,
            stream: stream,
            store: -> { ObservedResource.new(stream, self, loader) }
          )
        end
      end

      # ViewComponent instances are request-scoped. Observe only while the
      # component is rendering, then always release callbacks so the global
      # store registry cannot retain rendered component instances indefinitely.
      def render_in(...)
        start_observing!
        super
      ensure
        stop_observing!
        begin
          capture_reactive_dependency_snapshot! if respond_to?(:capture_reactive_dependency_snapshot!)
        ensure
          finish_observed_render!
        end
      end

      def start_observing!
        return self if @observation_subscriptions&.any?

        subscribe_to_observed_objects
        self
      end

      def stop_observing!
        Array(@observation_subscriptions).each(&:call)
        @observation_subscriptions = []
        self
      end
      
      private

      def finish_observed_render!
        (@observed_objects || {}).each_value do |store|
          store.finish_render! if store.respond_to?(:finish_render!)
        end
      end
      
      def subscribe_to_observed_objects
        @observation_subscriptions = []
        
        self.class.observed_object_definitions.each_key do |name|
          store = send(name)
          store.prepare_for_render! if store.respond_to?(:prepare_for_render!)
          
          # Subscribe to changes
          subscription = store.subscribe(self) do |changes|
            handle_observed_changes(name, changes)
          end
          
          @observation_subscriptions << subscription
        end
      end
      
      def handle_observed_changes(store_name, changes)
        @observed_changes ||= {}
        @observed_changes[store_name] ||= {}
        @observed_changes[store_name].merge!(changes.deep_dup)
        request_automatic_rerender if respond_to?(:request_automatic_rerender, true)
      end

      # Compatibility hook for renderers that expose observed changes through
      # an existing HTML fragment. Nokogiri owns parsing and serialization so
      # observed values cannot break out of the data attribute into markup.
      def add_observation_metadata
        return unless @observed_changes&.any?

        content = @_content.to_s
        return if content.empty?

        require "nokogiri"

        fragment = Nokogiri::HTML::DocumentFragment.parse(content)
        # This compatibility hook is an invalidation signal only. Observed
        # values, keys, and old/new pairs may be private application data and
        # must never be serialized into the page.
        encoded_changes = ERB::Util.json_escape(
          { "__invalidated" => { "__revision" => SecureRandom.hex(8) } }.to_json
        )
        root = fragment.children.find(&:element?)

        if root
          root.set_attribute("data-observed-changes", encoded_changes)
          @_content = fragment.to_html.html_safe
        else
          wrapper = Nokogiri::XML::Node.new("div", fragment)
          wrapper.set_attribute("data-observed-changes", encoded_changes)
          fragment.children.to_a.each { |child| wrapper.add_child(child) }
          @_content = wrapper.to_html.html_safe
        end
      end

    end

    # Request-scoped adapter for authoritative application data. It deliberately
    # retains no component subscriptions; shared Action Cable invalidation asks
    # the browser to render again and the loader reads the committed value.
    class ObservedResource
      attr_reader :id

      def initialize(id, owner, loader)
        @id = ObservableStore.normalize_stream_id(id)
        @owner = owner
        @loader = loader
        @snapshot_mutex = Mutex.new
        @has_rendered = false
        @render_prepared = false
        @snapshot_loaded = false
        @snapshot = nil
      end

      # A component can be rendered more than once in tests or custom render
      # pipelines. Each render gets one fresh authoritative read; every data
      # access during that render receives a defensive copy of that same
      # snapshot.
      def prepare_for_render!
        @snapshot_mutex.synchronize do
          # Reactive dependency initialization can legitimately read the
          # resource just before ViewComponent enters render_in. Preserve that
          # first read as the first render's snapshot; only a subsequent render
          # of the same component instance starts a new authoritative read.
          if @has_rendered || @render_prepared
            @snapshot_loaded = false
            @snapshot = nil
          end
          @render_prepared = true
        end
        self
      end

      def finish_render!
        @snapshot_mutex.synchronize do
          @has_rendered = true
          @render_prepared = false
          @snapshot_loaded = false
          @snapshot = nil
        end
        self
      end

      def data
        unless @snapshot_loaded
          # Run the loader OUTSIDE the lock: Ruby's Mutex is not reentrant, so a
          # loader that (transitively) reads this same resource would otherwise
          # deadlock, and loader I/O should not block other readers. Concurrent
          # first-loads may each run the loader; the first assignment wins.
          value = @owner.instance_exec(&@loader)
          raise TypeError, "observed_resource loader must return a Hash" unless value.is_a?(Hash)
          duplicated = value.respond_to?(:deep_dup) ? value.deep_dup : value.dup

          @snapshot_mutex.synchronize do
            unless @snapshot_loaded
              @snapshot = duplicated
              @snapshot_loaded = true
            end
          end
        end

        snapshot = @snapshot_mutex.synchronize { @snapshot }
        snapshot.respond_to?(:deep_dup) ? snapshot.deep_dup : snapshot.dup
      end

      def subscribe(_observer)
        raise ArgumentError, "a subscription callback is required" unless block_given?

        -> {}
      end
    end
    
    # Observable store that multiple components can share
    # SECURITY: Thread-safe implementation using Concurrent::Map
    class ObservableStore
      include ActiveSupport::Callbacks
      
      define_callbacks :change
      
      attr_reader :id
      
      # SECURITY: Use thread-safe Concurrent::Map instead of class variable
      require 'concurrent-ruby'
      @stores = Concurrent::Map.new
      @mutex = Mutex.new
      
      class << self
        # SECURITY: Thread-safe find_or_create using compute_if_absent
        def find_or_create(id)
          normalized_id = normalize_stream_id(id)
          @stores.compute_if_absent(normalized_id) { new(normalized_id) }
        end
        
        # SECURITY: Thread-safe find
        def find(id)
          @stores[normalize_stream_id(id)]
        end
        
        # SECURITY: Thread-safe clear with mutex protection
        def clear_all
          @mutex.synchronize do
            @stores.clear
          end
        end
        
        # SECURITY: Thread-safe store count for monitoring
        def store_count
          @stores.size
        end
        
        # SECURITY: Thread-safe store listing
        def all_store_ids
          @stores.keys
        end

        def stream_name(id)
          "swift_ui_rails:observed_store:#{normalize_stream_id(id)}"
        end

        def normalize_stream_id(id)
          value = id.to_s
          unless value.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/)
            raise ArgumentError, "observed stream id is invalid"
          end

          value
        end

        def invalidate(id)
          return false unless defined?(ActionCable) && ActionCable.respond_to?(:server)

          ActionCable.server.broadcast(
            stream_name(id),
            {
              action: "observed_change",
              store: normalize_stream_id(id),
              revision: SecureRandom.hex(8)
            }
          )
          true
        end
      end
      
      def initialize(id, initial_data = {})
        @id = self.class.normalize_stream_id(id)
        @data = initial_data.with_indifferent_access
        @data_mutex = Mutex.new
        # SECURITY: Use thread-safe Set and Hash
        @observers = Concurrent::Set.new
        @subscriptions = Concurrent::Hash.new
      end
      
      # SECURITY: Thread-safe update method
      def update(&block)
        changes = nil
        
        @data_mutex.synchronize do
          old_data = @data.deep_dup
          committed = false

          begin
            if block.arity == 1
              # Pass mutable data to block
              block.call(@data)
            else
              # Execute in context where data methods are available
              instance_exec(&block)
            end

            # Track what changed before committing. If either the mutation or
            # diffing raises, the original snapshot is restored atomically and
            # execution never reaches notification or Action Cable broadcast.
            changes = compute_changes(old_data, @data)
            committed = true
          ensure
            @data = old_data unless committed
          end
        end
        
        # Notify observers outside the mutex to prevent deadlocks
        if changes&.any?
          notify_observers(changes)
        end
        
        data_snapshot
      end
      
      # Set a specific value
      def set(key, value)
        if @data_mutex.owned?
          @data[key] = value
        else
          update { |data| data[key] = value }
        end
      end
      
      # SECURITY: Thread-safe getter
      def get(key)
        if @data_mutex.owned?
          @data[key]
        else
          @data_mutex.synchronize { @data[key].deep_dup }
        end
      end

      # Expose a snapshot so callers cannot mutate shared state without locking
      # or bypass change notifications.
      def data
        data_snapshot
      end
      
      # SECURITY: Thread-safe data snapshot
      def data_snapshot
        if @data_mutex.owned?
          @data.deep_dup
        else
          @data_mutex.synchronize { @data.deep_dup }
        end
      end
      
      # Subscribe to changes
      def subscribe(observer, &callback)
        raise ArgumentError, "a subscription callback is required" unless callback

        subscription_id = SecureRandom.hex(8)
        @subscriptions[subscription_id] = {
          observer: observer,
          callback: callback
        }
        @observers << observer
        
        # Return unsubscribe function
        -> { unsubscribe(subscription_id) }
      end
      
      # Unsubscribe from changes
      def unsubscribe(subscription_id)
        if sub = @subscriptions.delete(subscription_id)
          observer_still_subscribed = @subscriptions.any? do |_id, subscription|
            subscription[:observer].equal?(sub[:observer])
          end
          @observers.delete(sub[:observer]) unless observer_still_subscribed
        end
      end

      def subscription_count
        @subscriptions.size
      end
      
      # Notify all observers of changes
      def notify_observers(changes)
        run_callbacks :change do
          @subscriptions.each do |_, subscription|
            subscription[:callback].call(changes.deep_dup)
          rescue StandardError => error
            Rails.logger.error "ObservableStore #{id.inspect} subscriber failed: #{error.class}: #{error.message}"
          end
        end

        # Broadcast only an invalidation marker. Store contents may include
        # server-only data and are read again by the authorized component when
        # its encrypted snapshot update is rendered.
        self.class.invalidate(id)
      end
      
      # Reset store to initial state
      def reset(initial_data = {})
        update { @data = initial_data.with_indifferent_access }
      end
      
      private
      
      def compute_changes(old_data, new_data)
        changes = {}
        
        # Find added/modified keys
        new_data.each do |key, value|
          if !old_data.key?(key) || old_data[key] != value
            changes[key] = {
              old: old_data[key].respond_to?(:deep_dup) ? old_data[key].deep_dup : old_data[key],
              new: value.respond_to?(:deep_dup) ? value.deep_dup : value
            }
          end
        end
        
        # Find removed keys
        old_data.each do |key, value|
          unless new_data.key?(key)
            changes[key] = {
              old: value.respond_to?(:deep_dup) ? value.deep_dup : value,
              new: nil,
              removed: true
            }
          end
        end
        
        changes
      end
      
      # SECURITY: Thread-safe DSL for updating data
      def method_missing(method, *args)
        if method.to_s.end_with?('=')
          # Setter method - use thread-safe update
          key = method.to_s.chomp('=')
          set(key, args.first)
        elsif data_key?(method)
          # Getter method - thread-safe access
          get(method)
        else
          super
        end
      end
      
      def respond_to_missing?(method, include_private = false)
        method.to_s.end_with?('=') || data_key?(method) || super
      end

      def data_key?(key)
        if @data_mutex.owned?
          @data.key?(key)
        else
          @data_mutex.synchronize { @data.key?(key) }
        end
      end
    end
    
    # Publisher protocol for custom observable objects
    module Publisher
      extend ActiveSupport::Concern
      
      included do
        attr_reader :object_will_change_callbacks
      end
      
      def initialize(*)
        super
        @object_will_change_callbacks = []
      end
      
      # Call this before making changes
      def object_will_change
        @object_will_change_callbacks.each(&:call)
      end
      
      # Subscribe to changes
      def on_change(&block)
        @object_will_change_callbacks << block
        # Return unsubscribe function
        -> { @object_will_change_callbacks.delete(block) }
      end
    end
  end
end
