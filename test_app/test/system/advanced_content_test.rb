# frozen_string_literal: true

require "application_system_test_case"

class AdvancedContentTest < ApplicationSystemTestCase
  test "advanced content story renders and enhances every web-native family" do
    visit story_path(story: "advanced_content", variant: "content_families")

    assert_text "Rich content without unsafe escape hatches"
    assert_selector "#advanced-async-image[data-sui-async-image-phase='success']"
    assert_selector "#advanced-async-image img:not([hidden])"
    assert_selector "#advanced-chart svg[role='img']"
    assert_selector "#advanced-chart table.swift-ui-chart__data"
    assert_selector "#advanced-map[data-map-provider='schematic'] .swift-ui-map__marker", count: 3
    assert_text "no street tiles; not for navigation"
    assert_selector "#advanced-web-view[sandbox][data-web-view='same-origin']"
    assert_selector "#advanced-canvas[data-sui-canvas-ready='true'] canvas[role='img']"

    alpha = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const canvas = document.querySelector('#advanced-canvas canvas')
        const backingScale = canvas.width / 640
        return canvas
          .getContext('2d')
          .getImageData(75 * backingScale, 100 * backingScale, 1, 1).data[3]
      })()
    JAVASCRIPT
    assert_operator alpha, :>, 0
  end

  test "AsyncImage moves to its visible failure phase after a native image error" do
    visit story_path(story: "advanced_content", variant: "content_families")
    assert_selector "#advanced-async-image[data-sui-async-image-phase='success']"

    page.execute_script <<~JAVASCRIPT
      document.querySelector('#advanced-async-image img').src = '/definitely-missing-async-image.png'
    JAVASCRIPT

    assert_selector "#advanced-async-image[data-sui-async-image-phase='failure'][aria-busy='false']"
    assert_selector "#advanced-async-image [role='alert']:not([hidden])", text: "App mark unavailable"
    assert_selector "#advanced-async-image img[hidden]", visible: :all
  end
end
