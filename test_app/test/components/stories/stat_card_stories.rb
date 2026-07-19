# frozen_string_literal: true

class StatCardStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  control :stat_label, as: :text, default: "Requests / min"
  control :value, as: :text, default: "1,204"
  control :delta, as: :text, default: "+4.2%"
  control :trend, as: :select, options: %w[up down flat], default: "up"
  control :detail, as: :text, default: "Last 24 hours"

  def default(stat_label: "Requests / min", value: "1,204", delta: "+4.2%", trend: "up", detail: "Last 24 hours")
    StatCardComponent.new(stat_label: stat_label, value: value, delta: delta, trend: trend, detail: detail)
  end

  def dashboard_row(stat_label: "Requests / min", value: "1,204", delta: "+4.2%", trend: "up", detail: "Last 24 hours")
    content_tag(:div, class: "p-6 bg-slate-100 rounded-3xl") do
      swift_ui do
        grid(columns: 3, spacing: 12) do
          render StatCardComponent.new(stat_label: stat_label, value: value, delta: delta, trend: trend, detail: detail)
          render StatCardComponent.new(stat_label: "P95 latency", value: "182 ms", delta: "-3.1%", trend: "up", detail: "Across regions")
          render StatCardComponent.new(stat_label: "Error rate", value: "0.42%", delta: "+0.1%", trend: "down", detail: "5xx responses")
        end
      end
    end
  end
end
