# frozen_string_literal: true

require "test_helper"

class StatCardComponentTest < ViewComponent::TestCase
  def test_renders_label_value_delta_and_detail
    render_inline(StatCardComponent.new(
                    stat_label: "Requests / min",
                    value: "1,204",
                    delta: "+4.2%",
                    trend: "up",
                    detail: "Last 24 hours"
                  ))

    assert_text "Requests / min"
    assert_text "1,204"
    assert_text "+4.2%"
    assert_text "Last 24 hours"
    assert_selector ".bg-emerald-100"
  end

  def test_downward_trend_uses_the_negative_style
    render_inline(StatCardComponent.new(stat_label: "Errors", value: "0.4%", delta: "+0.1%", trend: "down"))

    assert_selector ".bg-rose-100"
  end

  def test_delta_badge_is_optional
    render_inline(StatCardComponent.new(stat_label: "Regions", value: "6"))

    assert_text "Regions"
    assert_no_selector ".bg-emerald-100"
    assert_no_selector ".bg-rose-100"
  end
end
