# frozen_string_literal: true

require "test_helper"

class StorybookStoriesParserTest < ActiveSupport::TestCase
  class InferredDefaultsStories < ViewComponent::Storybook::Stories
    DEFAULT_TITLE = "Inferred title"

    control :title, as: :text
    control :count, as: :number
    control :enabled, as: :boolean
    control :options, as: :object

    def default(
      title: DEFAULT_TITLE,
      count: 3,
      enabled: false,
      options: { nested: [1, 2] }
    )
      {}
    end
  end

  test "mock method objects expose parameters and infer control defaults" do
    code_object = ViewComponent::Storybook::StoriesParser::MockCodeObject.new(
      InferredDefaultsStories.name,
      __FILE__
    )
    method_object = code_object.meths.find { |method| method.name == :default }

    assert_equal ["title:", "DEFAULT_TITLE"], method_object.parameters.assoc("title:")
    assert_equal ["options:", "{ nested: [1, 2] }"], method_object.parameters.assoc("options:")

    InferredDefaultsStories.code_object = code_object
    args = InferredDefaultsStories.to_csf_params.fetch(:stories).first.fetch(:args)

    assert_equal "Inferred title", args[:title]
    assert_equal 3, args[:count]
    assert_equal false, args[:enabled]
    assert_equal({ nested: [1, 2] }, args[:options])
  end

  test "parser can run again after a callback raises" do
    parser = ViewComponent::Storybook::StoriesParser.new([])
    should_raise = true
    successful_callbacks = 0
    parser.after_parse do
      if should_raise
        should_raise = false
        raise "callback failed"
      end

      successful_callbacks += 1
    end

    assert_raises(RuntimeError) { parser.parse }
    parser.parse

    assert_equal 1, successful_callbacks
  end
end
