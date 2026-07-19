# frozen_string_literal: true

require "test_helper"

class NewDslMethodsControllerTest < ActiveSupport::TestCase
  test "new DSL methods work in rendered views without replacing application routes" do
    html = ApplicationController.render(
      inline: <<~ERB,
        <%= swift_ui do
          vstack do
            label("Test Label", for_input: "test-select")
            select(name: "test", selected: "2") do
              option("1", "Option 1")
              option("2", "Option 2", selected: true)
            end.ring_hover(2, "blue-500")

            div.break_inside("avoid").group_hover_opacity(50) do
              text("Test content")
            end

            button("Test Button")
              .flex_shrink(0)
              .title("Test tooltip")
              .style("color: red")
          end
        end %>
      ERB
      layout: false
    )
    document = Nokogiri::HTML.fragment(html)

    assert_equal "Test Label", document.at_css("label[for='test-select']")&.text
    assert_equal "Option 1", document.at_css("select[name='test'] option[value='1']")&.text
    assert document.at_css("select[name='test'] option[value='2'][selected='selected']")
    assert_includes html, "hover:ring-2"
    assert_includes html, "hover:ring-blue-500"
    assert_includes html, "break-inside-avoid"
    assert_includes html, "group-hover:opacity-50"
    assert_includes html, "flex-shrink-0"
    assert document.at_css("[title='Test tooltip']")
    assert_includes document.at_css("button[style]")&.[]("style"), "color: red"
  end
end
