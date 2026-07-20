# frozen_string_literal: true

require "digest"
require "monitor"

# Persists server-owned props and typed component state for Storybook sessions.
class StorySession
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :story_name, :string
  attribute :variant, :string
  attribute :session_id, :string
  attribute :state, default: -> { {} }
  attribute :props, default: -> { {} }
  attribute :created_at, :datetime, default: -> { Time.current }

  validates :story_name, :variant, :session_id, presence: true

  SESSION_ID_PATTERN = /\A[A-Za-z0-9_-]{1,128}\z/.freeze
  SESSION_LOCKS = Array.new(64) { Monitor.new }.freeze

  def self.find_or_create(story_name, variant, session_id)
    key = cache_key(story_name, variant, session_id)
    synchronize(story_name, variant, session_id) do
      data = Rails.cache.read(key)

      if data
        new(data.symbolize_keys)
      else
        session = new(
          story_name: story_name,
          variant: variant,
          session_id: session_id
        )
        session.save!
        session
      end
    end
  end

  def self.find(story_name, variant, session_id)
    key = cache_key(story_name, variant, session_id)
    data = Rails.cache.read(key)
    return nil unless data

    new(data.symbolize_keys)
  end

  def self.synchronize(story_name, variant, session_id, &block)
    key = cache_key(story_name, variant, session_id)
    SESSION_LOCKS.fetch(key.hash % SESSION_LOCKS.length).synchronize(&block)
  end

  def save!
    raise ActiveModel::ValidationError, self unless valid?

    Rails.cache.write(cache_key, attributes, expires_in: 30.minutes)
    Rails.cache.write(
      "story_session_lookup:#{session_id}",
      { story_name: story_name, variant: variant },
      expires_in: 30.minutes
    )
    self
  end

  def component_instance
    entry = resolve_story_entry!
    story_variant = resolve_story_variant!(entry)
    story_instance = entry.story_class.new

    # Get the story method parameters to filter props
    method_obj = story_instance.method(story_variant)
    method_params = method_obj.parameters

    # Filter props to only include valid parameters
    accepted_params = method_params.select { |type, name| [ :key, :keyreq ].include?(type) }.map(&:last)
    filtered_props = props.symbolize_keys.slice(*accepted_params)

    # Create component using StoryRenderer for proper context
    renderer = StoryRenderer.new(ApplicationController.new)
    component = renderer.render_story(story_instance, story_variant, **filtered_props)

    if component.is_a?(ViewComponent::Base) && reactive_state_component?(component)
      # Mirror save_component_state's contract: restore only declared state
      # keys, and symbolize them so the component's symbol-keyed getters read
      # them back (persisted state is stringified for the cache).
      declared = component.class.state_definitions.keys
      component.state_values = state.symbolize_keys.slice(*declared)
    end

    component
  rescue NameError, NoMethodError => e
    Rails.logger.error "Error creating component instance: #{e.message}"
    nil
  end

  def update_state!(new_state)
    atomic_merge!(:state, new_state)
  end

  def update_props(new_props)
    atomic_merge!(:props, new_props)
  end

  def update_props!(new_props)
    update_props(new_props)
  end

  def save_component_state(component_instance)
    return unless reactive_state_component?(component_instance)

    declared = component_instance.class.state_definitions.keys
    persisted = component_instance.state_values.slice(*declared).stringify_keys
    update_state!(persisted)
  end

  # Alias for accessing current state - used by storybook controller
  def current_state
    state
  end

  def reset_state!
    with_atomic_update { self.state = {} }
  end

  private

  def reactive_state_component?(component)
    component.class.respond_to?(:state_definitions) &&
      component.class.state_definitions.any? &&
      component.respond_to?(:state_values) &&
      component.respond_to?(:state_values=)
  end

  def atomic_merge!(attribute, updates)
    with_atomic_update do |persisted|
      persisted_value = if persisted&.key?(attribute.to_s)
        persisted.fetch(attribute.to_s)
      elsif persisted&.key?(attribute)
        persisted.fetch(attribute)
      else
        public_send(attribute)
      end

      public_send("#{attribute}=", (persisted_value || {}).merge(updates))
    end
  end

  def with_atomic_update
    self.class.synchronize(story_name, variant, session_id) do
      persisted = Rails.cache.read(cache_key)
      yield persisted
      save!
    end
  end

  def cache_key
    self.class.cache_key(story_name, variant, session_id)
  end

  def self.cache_key(story_name, variant, session_id)
    entry = StorybookStoryRegistry.fetch(story_name)
    raise SwiftUIRails::SecurityError, "Unauthorized story: #{story_name}" unless entry

    allowed_variant = entry.variants.any? { |candidate| candidate.to_s == variant.to_s }
    raise SwiftUIRails::SecurityError, "Unauthorized story variant: #{variant}" unless allowed_variant

    unless valid_session_id?(session_id)
      raise SwiftUIRails::SecurityError, "Invalid story session identifier"
    end

    identity = [ entry.name, variant.to_s, session_id ].join("\0")
    "story_session:#{Digest::SHA256.hexdigest(identity)}"
  end

  def self.valid_session_id?(session_id)
    session_id.is_a?(String) && session_id.match?(SESSION_ID_PATTERN)
  end

  def resolve_story_entry!
    entry = StorybookStoryRegistry.fetch(story_name)
    return entry if entry

    Rails.logger.error "[SECURITY] Attempted to instantiate unauthorized story: #{story_name}"
    raise SwiftUIRails::SecurityError, "Unauthorized story: #{story_name}"
  end

  def resolve_story_variant!(entry)
    story_variant = entry.variants.find { |allowed_variant| allowed_variant.to_s == variant.to_s }
    return story_variant if story_variant

    Rails.logger.error "[SECURITY] Attempted to invoke unauthorized story variant: #{entry.name}/#{variant}"
    raise SwiftUIRails::SecurityError, "Unauthorized story variant: #{variant}"
  end
end
