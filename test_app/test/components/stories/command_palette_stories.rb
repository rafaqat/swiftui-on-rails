# frozen_string_literal: true

class CommandPaletteStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  control :hint, as: :text, default: "Jump anywhere"
  control :placeholder, as: :text, default: "Search demos, labs, and pages…"

  def default(hint: "Jump anywhere", placeholder: "Search demos, labs, and pages…")
    CommandPaletteComponent.new(hint: hint, placeholder: placeholder)
  end
end
