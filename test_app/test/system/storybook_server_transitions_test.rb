# frozen_string_literal: true

require "application_system_test_case"

class StorybookServerTransitionsTest < ApplicationSystemTestCase
  test "text and boolean controls update through one explicit Rails GET" do
    visit story_path(story: "dsl_button")

    fill_in "text", with: "Deploy"
    check "disabled"
    click_button "Apply controls"

    assert_selector "#component-preview button[disabled]", text: "Deploy", wait: 10
    assert_includes URI.parse(page.current_url).query, "text=Deploy"
  end

  test "a true boolean default can be submitted as false" do
    visit story_path(story: "dsl_button")

    assert_selector "#component-preview button.transition", text: "Click Me"
    uncheck "transition_enabled"
    click_button "Apply controls"

    assert_no_selector "#component-preview button.transition", text: "Click Me", wait: 10
    assert_selector "#component-preview button", text: "Click Me"
  end

  test "select controls update button size and shape" do
    visit story_path(story: "dsl_button")

    select "Xl", from: "size"
    select "Full", from: "rounded"
    click_button "Apply controls"

    assert_selector "#component-preview button.text-xl.rounded-full", text: "Click Me", wait: 10
  end

  test "variant links are ordinary navigations and can switch back" do
    visit story_path(story: "dsl_card")

    find("a[data-variant='card_gallery']").click
    assert_selector "#component-preview", text: "DSL Card Gallery", wait: 10
    assert_selector "#component-preview", text: "Simple Card"
    assert_selector "#component-preview", text: "Interactive Card"
    assert_selector "#component-preview", text: "Feature Card"
    assert_current_path story_path(story: "dsl_card", story_variant: "card_gallery")

    find("a[data-variant='default']").click
    assert_selector "#component-preview", text: "DSL Card - Composition Pattern", wait: 10
    assert_current_path story_path(story: "dsl_card", story_variant: "default")
  end
end
