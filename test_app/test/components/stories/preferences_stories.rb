# frozen_string_literal: true

class PreferencesStories < ViewComponent::Storybook::Stories
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Context
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  control :panel_title, as: :text, default: "Workspace preferences"

  def default(panel_title: "Workspace preferences")
    PreferencesComponent.new(panel_title: panel_title)
  end
end
