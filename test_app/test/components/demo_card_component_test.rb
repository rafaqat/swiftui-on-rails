# frozen_string_literal: true

require "test_helper"

class DemoCardComponentTest < ViewComponent::TestCase
  def sample_demo
    DemoCatalog.fetch("operations")
  end

  def test_renders_name_description_and_model_badge
    render_inline(DemoCardComponent.new(demo: sample_demo))

    assert_text "Live Operations Room"
    assert_text "Action Cable"
    assert_selector "a[data-demo-card='operations']"
  end

  def test_links_to_the_demo_destination
    render_inline(DemoCardComponent.new(demo: sample_demo))

    assert_selector "a[href='/showcase/operations']"
  end
end
