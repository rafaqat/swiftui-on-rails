# frozen_string_literal: true

# Renders story output while preserving Rails' SafeBuffer trust boundary.
class StoryHtmlWrapperComponent < ViewComponent::Base
  def initialize(html_content:)
    @html_content = html_content
  end

  def call
    return "" if @html_content.nil?
    return @html_content if @html_content.respond_to?(:html_safe?) && @html_content.html_safe?

    ERB::Util.html_escape(@html_content.to_s)
  end

  def inspect
    "#<StoryHtmlWrapperComponent content_length=#{@html_content&.length || 0}>"
  end
end
