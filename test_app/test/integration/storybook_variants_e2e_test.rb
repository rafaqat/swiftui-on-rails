# frozen_string_literal: true

require "test_helper"

class StorybookVariantsE2eTest < ActionDispatch::IntegrationTest
  test "all registered story classes and variants render through the server route" do
    StorybookStoryRegistry.all.each do |entry|
      assert entry.story_class < ViewComponent::Storybook::Stories
      assert_predicate entry.variants, :any?

      entry.variants.each do |variant|
        get story_path(story: entry.name, story_variant: variant)

        assert_response :success,
                        "#{entry.name}/#{variant} should render: #{response.body.first(200)}"
        assert_select "h1", text: /#{entry.name.sub(/_component\z/, '').titleize}/
        assert_select "h2", text: "Preview Controls"
        assert_select "h2", text: "Preview"
        assert_select "#component-preview[data-sui-story=?]", entry.name, count: 1
        assert_not_includes response.body, "Unable to render component preview."
      end
    end
  end

  test "every story exposes explicit controls and trusted variant links" do
    StorybookStoryRegistry.all.each do |entry|
      get story_path(story: entry.name)

      assert_response :success
      assert_select "form#storybook-controls[action=?][method='get']",
                    story_path(story: entry.name),
                    count: 1

      if entry.variants.many?
        assert_select "nav[aria-label='Story variants']", count: 1
        entry.variants.each do |variant|
          assert_select "a[data-variant=?][href=?]",
                        variant.to_s,
                        story_path(story: entry.name, story_variant: variant),
                        count: 1
        end
      end
    end
  end

  test "Storybook shell never emits application JavaScript vocabulary" do
    StorybookStoryRegistry.all.each do |entry|
      get story_path(story: entry.name)

      assert_response :success
      assert_select "[data-controller], [data-action]", count: 0
      refute_match(/data-[a-z0-9-]+-target=/, response.body)
      refute_match(/\w+->\w+#\w+/, response.body)
    end
  end
end
