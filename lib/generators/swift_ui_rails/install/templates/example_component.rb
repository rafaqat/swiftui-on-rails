# frozen_string_literal: true

# Demonstrates typed state, semantic modifiers, and signed component actions.
class ExampleComponent < ApplicationComponent
  prop :title, type: String, default: 'Hello from SwiftUI Rails!'
  prop :description, type: String

  state :counter, 0, type: Integer
  state :show_details, false, type: [TrueClass, FalseClass]

  computed :button_text do
    show_details ? 'Hide Details' : 'Show Details'
  end

  swift_ui do
    component = @component

    card(elevation: 2).padding(6) do
      vstack(spacing: 16) do
        # Title
        text(title).text_style(:title)

        # Counter section
        hstack(spacing: 12) do
          button('-')
            .on_tap { component.counter -= 1 }
            .button_style(:danger)
            .button_size(:regular)
          text("Count: #{component.counter}").text_style(:headline)
          button('+')
            .on_tap { component.counter += 1 }
            .button_style(:primary)
            .button_size(:regular)
        end

        # Toggle section
        button(component.button_text)
          .on_tap { component.show_details = !component.show_details }
          .button_style(:bordered_prominent)
          .button_size(:regular)

        # Conditional content
        if component.show_details && component.description
          divider.my(4)
          text(component.description).text_style(:supporting)
        end
      end
    end
  end
end
