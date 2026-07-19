require "test_helper"

class CounterRenderTest < ActiveSupport::TestCase
  include SwiftUIRails::Helpers
  
  test "counter component renders framework-neutral semantic actions" do
    component = CounterComponent.new(
      initial_count: 5,
      step: 2,
      label: "Test Counter"
    )
    
    output = ApplicationController.render(component, layout: false)
    fragment = Nokogiri::HTML.fragment(output)

    assert fragment.at_css("[data-sui-root='1'][data-sui-component='CounterComponent']")
    assert_equal "Test Counter: 5", fragment.at_css("[data-counter-label='true']").text
    assert_equal "5", fragment.at_css("[data-counter-display='true']").text
    assert_equal 3, fragment.css("button[data-sui-actions]").length
    refute_match(/data-(?:controller|action|counter-target)=/, output)
  end
  
  test "DSL deterministically rejects application controller metadata" do
    # Create a view context for testing
    view_context = ApplicationController.new.view_context
    
    # Create a DSL context with the view context
    dsl_context = SwiftUIRails::DSLContext.new(view_context)
    
    # Test the DSL directly
    result = dsl_context.instance_eval do
      div(data: { controller: "test", "test-value": "hello" }, id: "my-div") do
        text("Content")
      end
    end
    
    error = assert_raises(SwiftUIRails::Error) { result.to_s }
    assert_match(/application JavaScript|data-controller/i, error.message)
  end
end
