require "test_helper"
require "erb"

class ERBRenderingTest < ActiveSupport::TestCase
  test "ERB interpolates swift_ui output" do
    view = build_view
    template = <<~ERB
      <section>
        <%= swift_ui do
          vstack(spacing: 24).p(8) do
            text("ERB content")
          end
        end %>
      </section>
    ERB

    result = ERB.new(template).result(view.instance_eval { binding })
    fragment = Nokogiri::HTML.fragment(result)

    assert_equal "ERB content", fragment.at_css("section div.flex.flex-col.p-8 span")&.text
    assert_includes result, 'style="gap: 24px"'
    refute_includes result, "Routing Error"
  end

  private

  def build_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |view|
      view.extend(SwiftUIRails::Helpers)
    end
  end
end
