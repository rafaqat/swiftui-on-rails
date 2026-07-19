# frozen_string_literal: true

class ToastStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  control :message, as: :text, default: "Flight plan updated."
  control :variant, as: :select, options: %w[info success warning error], default: "success"
  control :duration, as: :number, default: 5000, min: 1000, max: 30_000

  def default(message: "Flight plan updated.", variant: "success", duration: 5000)
    ToastComponent.new(message: message, variant: variant, duration: duration.to_i)
  end

  def stacked(message: "Flight plan updated.", variant: "success", duration: 5000)
    content_tag(:div, class: "p-6 bg-slate-100 rounded-3xl") do
      swift_ui do
        vstack(spacing: 12, alignment: :start) do
          render ToastComponent.new(message: message, variant: variant, duration: duration.to_i)
          render ToastComponent.new(message: "Board reset.", variant: "info")
          render ToastComponent.new(message: "In Flight is at its limit of 4 cards", variant: "error")
        end
      end
    end
  end
end
