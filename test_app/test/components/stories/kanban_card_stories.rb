# frozen_string_literal: true

class KanbanCardStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  control :title, as: :text, default: "Orbital navigation pass"
  control :topic, as: :select, options: %w[guidance systems ops comms], default: "guidance"
  control :priority, as: :select, options: %w[low medium high], default: "high"

  def default(title: "Orbital navigation pass", topic: "guidance", priority: "high")
    KanbanCardComponent.new(title: title, topic: topic, priority: priority)
  end

  def board_column(title: "Orbital navigation pass", topic: "guidance", priority: "high")
    content_tag(:div, class: "max-w-xs p-6 bg-slate-100 rounded-3xl") do
      swift_ui do
        vstack(spacing: 8, alignment: :stretch) do
          render KanbanCardComponent.new(title: title, topic: topic, priority: priority)
          render KanbanCardComponent.new(title: "Fuel margin audit", topic: "systems", priority: "medium")
          render KanbanCardComponent.new(title: "Crew launch brief", topic: "ops", priority: "low")
        end
      end
    end
  end
end
