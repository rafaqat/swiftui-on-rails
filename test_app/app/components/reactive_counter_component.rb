# frozen_string_literal: true

# A small reference component used by the compatibility lab and end-to-end
# tests. It exercises server-owned State, a browser-editable Binding, effects,
# and signed action round trips without delegating behavior to bespoke JS.
class ReactiveCounterComponent < SwiftUIRails::Component::Base
  prop :label, type: String, default: "Scientific samples"

  state :count, 0, type: Integer
  binding :step, type: Integer, default: 1

  swift_ui do
    component = @component

    vstack(alignment: :start, spacing: 12, class: "rounded-xl border border-slate-200 bg-white p-5") do
      text(component.label).font_weight("semibold").text_color("slate-700")
      text(component.count.to_s, class: "text-4xl font-black tabular-nums", data: { reactive_counter_display: true })

      label("Step", for_input: "reactive-counter-step")
      input(
        id: "reactive-counter-step",
        type: "number",
        min: 1,
        max: 100,
        **component.step.input_attributes
      )

      control_group(label: "Counter actions") do
        button("Decrease").button_style(:secondary).on_click do |_event|
          component.count = [component.count - component.step.value, 0].max
        end
        button("Increase").button_style(:primary).on_click do |_event|
          component.count += component.step.value
        end
      end
    end
  end
end
