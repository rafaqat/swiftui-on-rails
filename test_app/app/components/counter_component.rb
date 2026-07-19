# frozen_string_literal: true

class CounterComponent < SwiftUIRails::Component::Base
  prop :initial_count, type: Integer, default: 0
  prop :step, type: Integer, default: 1
  prop :label, type: String, default: "Counter"
  prop :counter_id, type: String, default: -> { "counter-#{SecureRandom.hex(4)}" }

  state :count, -> { initial_count }, type: Integer

  swift_ui do
    component = @component

    vstack(spacing: 4) do
      text("#{component.label}: #{component.count}")
        .font_size("2xl")
        .font_weight("bold")
        .tw("transition-colors duration-200")
        .data(counter_label: true)

      text(component.count.to_s)
        .font_size("6xl")
        .font_weight("black")
        .tw("transition-all duration-300")
        .data(counter_display: true)

      hstack(spacing: 2) do
        decrement = button("-")
          .bg("red-500")
          .text_color("white")
          .px(4)
          .py(2)
          .rounded("lg")
          .tw("transition-opacity duration-200")
        decrement.on_click { component.count -= component.step }

        reset = button("Reset")
          .bg("gray-500")
          .text_color("white")
          .px(4)
          .py(2)
          .rounded("lg")
        reset.on_click { component.count = component.initial_count }

        increment = button("+")
          .bg("green-500")
          .text_color("white")
          .px(4)
          .py(2)
          .rounded("lg")
          .tw("transition-opacity duration-200")
        increment.on_click { component.count += component.step }
      end
    end
      .p(6)
      .bg("white")
      .rounded("xl")
      .shadow("lg")
      .border
      .border_color("gray-200")
      .data(counter: true)
      .attr("id", component.counter_id)
  end
end
