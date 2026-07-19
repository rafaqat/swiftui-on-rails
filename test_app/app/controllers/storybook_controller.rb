# frozen_string_literal: true

class StorybookController < ApplicationController
  def index
    @stories = StoryCatalog.entries.filter_map do |metadata|
      entry = StorybookStoryRegistry.fetch(metadata.fetch(:path))
      next unless entry

      metadata.merge(file: entry.file, variants: entry.variants)
    end
  end

  def show
    entry = StorybookStoryRegistry.fetch(params[:story])
    unless entry
      flash[:alert] = "Story not found: #{params[:story]}"
      redirect_to rails_stories_path
      return
    end

    requested_variant = params[:variant].presence || params[:story_variant].presence
    @story_variant = resolve_story_variant(entry, requested_variant)
    unless @story_variant
      flash[:alert] = "Story variant not found: #{requested_variant}"
      redirect_to rails_stories_path
      return
    end

    prepare_story(entry)
    prepare_source(entry)
    prepare_server_preview(entry)
  end

  private

  def prepare_story(entry)
    @story_class = entry.story_class
    @story_class_name = @story_class.name
    @story_key = entry.name
    @story_name = entry.name.sub(/_component\z/, "").titleize
    @session_id = session[:storybook_session_id] ||= SecureRandom.hex(16)
    @component_name = entry.component_name
    @component_class = entry.component_class
    @story_instance = @story_class.new
    @available_stories = entry.variants
    @story_config = extract_story_config(@story_class)
    @component_props = build_component_props(@story_config)
  end

  def prepare_source(entry)
    @dsl_story = StoryCatalog.source_display?(entry.name)
    return unless @dsl_story

    if StoryCatalog.source_from_component?(entry.name)
      @story_source_path, @story_source_code = StorySourceExtractor.component_source(@component_class)
    end

    @story_source_path ||= entry.file
    @story_source_code ||= StorySourceExtractor.method_source(entry.file, @story_variant.to_s)
  end

  # Storybook is a normal Rails read model. A GET resolves props, updates the
  # browser-owned story session, and renders both preview and inspector from
  # the same server state. The browser has no parallel Storybook state model.
  def prepare_server_preview(entry)
    @state_data = @component_props.to_h do |name, value|
      ["prop_#{name}", value]
    end
    return unless @component_class

    @story_session = StorySession.find_or_create(entry.name, @story_variant.to_s, @session_id)
    @story_session.update_props(@component_props)
    @component_instance = @story_session.component_instance
    @state_data.merge!(@story_session.current_state || {})
  end

  def resolve_story_variant(entry, requested_variant)
    if requested_variant.present?
      requested_name = requested_variant.to_s
      return entry.variants.find { |variant| variant.to_s == requested_name }
    end

    entry.variants.include?(:default) ? :default : entry.variants.first
  end

  def extract_story_config(story_class)
    controls_data = story_class.send(:controls).instance_variable_get(:@controls) || []
    controls = controls_data.to_h do |control_data|
      control = control_data.except(:only, :except)
      control[:type] = control.delete(:as)
      [control_data.fetch(:param), control]
    end

    { component: @component_class, controls: controls, layout: nil }
  end

  def build_component_props(story_config)
    story_config.fetch(:controls).to_h do |key, control|
      value = normalized_control_value(key, control)
      [key, coerce_control_value(value, control)]
    end
  end

  def normalized_control_value(key, control)
    submitted = params[key]
    return control[:default] if submitted.nil?

    if submitted == ""
      return nil if optional_prop?(key)

      return control[:default]
    end

    submitted
  end

  def coerce_control_value(value, control)
    case control[:type]
    when :boolean
      ActiveModel::Type::Boolean.new.cast(value)
    when :number
      value.present? ? value.to_i : value
    when :select
      option = Array(control[:options]).find { |candidate| candidate.to_s == value.to_s }
      option.nil? ? control[:default] : option
    else
      value
    end
  end

  def optional_prop?(key)
    %i[
      background_color
      custom_background
      custom_text_color
      font_size
      padding_x
      padding_y
      text_color
    ].include?(key.to_sym)
  end
end
