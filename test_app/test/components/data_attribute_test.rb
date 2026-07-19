require "test_helper"

class DataAttributeTest < ActiveSupport::TestCase
  include ActionView::Helpers::TagHelper

  test "Rails content_tag preserves the semantic action map" do
    actions = { click: "a_0123456789abcdef0123456789abcdef" }
    result = content_tag(:button, "Click", data: { sui_actions: JSON.generate(actions) })
    button = Nokogiri::HTML.fragment(result).at_css("button")

    assert_equal({ "click" => "a_0123456789abcdef0123456789abcdef" },
      JSON.parse(button["data-sui-actions"]))
  end

  test "explicit semantic binding attributes survive Rails tag rendering" do
    attrs = { "data-sui-binding" => "query", "data-sui-binding-type" => "string" }
    result = content_tag(:button, "Click", attrs)
    button = Nokogiri::HTML.fragment(result).at_css("button")

    assert_equal "query", button["data-sui-binding"]
    assert_equal "string", button["data-sui-binding-type"]
  end
end
