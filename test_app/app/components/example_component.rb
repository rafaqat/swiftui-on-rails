# frozen_string_literal: true

class ExampleComponent < ApplicationComponent
  prop :title, type: String, default: "Hello from SwiftUI Rails!"
  prop :description, type: String

  state :counter, 0, type: Integer
  state :show_details, false, type: :boolean

  computed :button_text do
    show_details ? "Hide Details" : "Show Details"
  end

  effect :counter do |new_value, old_value|
    Rails.logger.info "Counter changed from #{old_value} to #{new_value}"
  end

  effect :show_details do |new_value, old_value|
    Rails.logger.info "Show details toggled: #{old_value} -> #{new_value}"
  end

  swift_ui do
    vstack(spacing: 16, class: "bg-white rounded-lg shadow-md p-6") do
      text(title, class: "text-2xl font-bold")

      hstack(spacing: 12) do
        decrement = button("-", class: "px-4 py-2 bg-red-500 text-white rounded")
        decrement.on_click { @component.counter = [@component.counter - 1, 0].max }

        text("Count: #{counter}", class: "text-lg")

        increment = button("+", class: "px-4 py-2 bg-green-500 text-white rounded")
        increment.on_click { @component.counter += 1 }
      end

      toggle = button(
        button_text,
        class: "px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
      )
      toggle.on_click { @component.show_details = !@component.show_details }

      if show_details && description
        hr(class: "border-t border-gray-300 my-4")
        text(description, class: "text-gray-600")
      end
    end
  end

end
