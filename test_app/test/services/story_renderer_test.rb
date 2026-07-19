# frozen_string_literal: true

require "test_helper"

class StoryRendererTest < ViewComponent::TestCase
  test "ordinary story strings are rendered as text" do
    render_inline(
      StoryHtmlWrapperComponent.new(
        html_content: '<img id="story-xss" src="x" onerror="alert(1)">'
      )
    )

    assert_no_selector "#story-xss"
    assert_text '<img id="story-xss"'
  end

  test "explicitly safe story buffers retain trusted markup" do
    render_inline(
      StoryHtmlWrapperComponent.new(
        html_content: "<strong>Trusted story markup</strong>".html_safe
      )
    )

    assert_selector "strong", text: "Trusted story markup"
  end
end
