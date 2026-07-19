# frozen_string_literal: true

# Read-only Storybook fixture for the DSL-authored IDE shell. Source and data
# deliberately are not Storybook controls; edits flow through the playground's
# bounded compiler endpoint instead of component construction from request data.
class SwiftUiRailsPlaygroundStories < ViewComponent::Storybook::Stories
  def ide_shell
    example = Showcase::Playground::Examples.find("product-catalog")
    initial_result = Showcase::Playground::Runner.call(
      source: example.source,
      data_json: example.data_json,
      view_context: view_context
    )

    SwiftUiRailsPlaygroundComponent.new(
      examples: Showcase::Playground::Examples.all,
      selected_example: example,
      initial_result: initial_result,
      compile_url: "/showcase/playground/compile"
    )
  end
end
