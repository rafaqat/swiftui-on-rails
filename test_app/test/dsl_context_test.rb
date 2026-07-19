require "test_helper"

class DSLContextTest < ActiveSupport::TestCase
  test "DSL context returns a chainable element" do
    context = SwiftUIRails::DSLContext.new(build_view)
    element = context.vstack(spacing: 24)
    modified = element.p(8)

    assert_instance_of SwiftUIRails::DSL::Element, element
    assert_same element, modified
    assert_match(/class="[^"]*flex flex-col[^"]*p-8/, modified.to_s)
    assert_includes modified.to_s, 'style="gap: 24px"'
  end

  test "swift_ui flushes registered elements as safe HTML" do
    result = build_view.swift_ui do
      vstack(spacing: 24).p(8) do
        text("Test content")
      end
    end

    assert_predicate result, :html_safe?
    assert_includes result, "Test content"
    assert_match(/class="[^"]*p-8/, result)
    assert_includes result, 'style="gap: 24px"'
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
