# frozen_string_literal: true

# StoryRenderer provides a rendering context for ViewComponent stories
# that mimics the ViewComponent test environment, making render() 
# behave like render_inline()
class StoryRenderer
  include ViewComponent::TestHelpers
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include ActionView::Helpers::OutputSafetyHelper
  include ActionView::Helpers::CaptureHelper
  
  attr_reader :controller, :request
  
  def initialize(controller)
    @controller = controller
    @request = controller.request
    @rendered_content = nil
  end
  
  # Required for ViewComponent::TestHelpers
  def vc_test_controller
    @vc_test_controller ||= controller
  end
  
  # Override render to use render_inline behavior
  def render(component, &block)
    # Store the component for later retrieval
    @last_component = component
    
    # Use ViewComponent's render_inline which returns actual HTML
    @rendered_content = if Rails.version.to_f >= 6.1
      vc_test_controller.view_context.render(component, {}, &block)
    else
      vc_test_controller.view_context.render_component(component, &block)
    end
    
    # Return the actual HTML for inline use in stories
    @rendered_content
  end
  
  # Execute a story method in this rendering context
  def render_story(story_instance, story_method, **kwargs)
    # Ensure the story instance has access to the view context for swift_ui helper
    if story_instance.respond_to?(:view_context=)
      story_instance.view_context = controller.view_context
    end
    
    # Instead of copying methods, execute the story method directly
    # but make sure it uses our render method
    story_instance.define_singleton_method(:render) do |component, &block|
      # Call StoryRenderer's render method
      @story_renderer.render(component, &block)
    end
    
    # Store reference to self so story can call our render
    story_instance.instance_variable_set(:@story_renderer, self)
    
    # Get the story method's parameters
    method_params = story_instance.method(story_method).parameters
    
    # Filter kwargs to only include parameters the story method accepts
    accepted_params = method_params.select { |type, name| [:key, :keyreq].include?(type) }.map(&:last)
    filtered_kwargs = kwargs.slice(*accepted_params)
    
    # Make view context available to the story instance
    view_context = controller.view_context
    story_instance.define_singleton_method(:view_context) { view_context }
    
    # Ensure the story has access to swift_ui helper
    unless story_instance.respond_to?(:swift_ui)
      story_instance.define_singleton_method(:swift_ui) do |&block|
        view_context.swift_ui(&block)
      end
    end
    
    # Execute the story method
    result = if filtered_kwargs.any?
      story_instance.send(story_method, **filtered_kwargs)
    else
      story_instance.send(story_method)
    end
    
    # For simple stories that return component instances, return the component
    # For complex stories that return HTML, wrap in a simple component
    if result.respond_to?(:call) && result.is_a?(ViewComponent::Base)
      result
    elsif result.is_a?(ActiveSupport::SafeBuffer) || result.is_a?(String)
      # For HTML content (including swift_ui DSL output), use the wrapper component
      StoryHtmlWrapperComponent.new(html_content: result)
    else
      # Default case - convert to string
      StoryHtmlWrapperComponent.new(html_content: result.to_s)
    end
  end
end
