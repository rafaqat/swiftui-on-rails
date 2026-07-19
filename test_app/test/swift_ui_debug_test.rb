require "test_helper"

class SwiftUIDebugTest < ActiveSupport::TestCase
  test "swift_ui evaluates the block in a DSL context" do
    receiver = nil
    result = build_view.swift_ui do
      receiver = self
      vstack(spacing: 24).p(8) do
        text("Context content")
      end
    end

    assert_instance_of SwiftUIRails::DSLContext, receiver
    assert_predicate result, :html_safe?
    assert_includes result, "Context content"
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
