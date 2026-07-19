# frozen_string_literal: true

require "application_system_test_case"

class PortableWorkflowsTest < ApplicationSystemTestCase
  test "reorder swipe and document workflows keep native alternatives under enhancement" do
    visit story_path(story: "wwdc26_workflows", variant: "portable_workflows")

    assert_selector "#component-preview #delivery-order [role='listitem']", count: 4
    assert_selector "#component-preview #delivery-order button.swift-ui-reorder-down", count: 4
    assert_selector "#component-preview #delivery-order button.swift-ui-reorder-up", count: 4
    first_enabled_move = find(
      "#component-preview #delivery-order [role='listitem']:first-child button",
      text: "Move down"
    )
    page.execute_script("arguments[0].focus()", first_enabled_move)
    assert_selector "#component-preview #delivery-order button:focus"

    first_enabled_move.click
    wait_for_preview_value("#delivery-order [role='listitem']:first-child .text-lg", "Design")

    assert_selector "#component-preview #delivery-order [role='listitem']:first-child .text-lg", text: "Design"
    labels = all("#component-preview #delivery-order .swift-ui-reorder-content .text-lg").map(&:text)
    assert_equal [ "Design", "Research", "Build", "Release" ], labels

    assert_selector "#component-preview #workflow-swipe button", text: "Archive", count: 2
    assert_selector "#component-preview #workflow-swipe button", text: "Delete", count: 2
    assert_selector "#component-preview #workflow-swipe .swift-ui-swipe-actions-buttons",
      visible: :visible,
      count: 2

    swipe_row = find("#component-preview #workflow-swipe .swift-ui-swipe-actions", match: :first)
    page.execute_script(<<~JS, swipe_row)
      const row = arguments[0]
      row.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 41, clientX: 180, clientY: 20 }))
      row.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 41, clientX: 40, clientY: 22 }))
    JS
    assert_selector "#component-preview #workflow-swipe .swift-ui-swipe-actions[data-sui-swipe-state='revealed']"
    assert_selector "#component-preview #workflow-swipe [role='status']",
      text: "Roadmap review actions available",
      visible: :all

    swipe_row.find("button", text: "Archive").click
    wait_for_preview_value("#workflow-swipe [role='status']", "Roadmap marked archived")

    assert_selector "#component-preview #workflow-swipe [role='status']",
      text: "Roadmap marked archived",
      visible: :all

    assert_selector "#component-preview #workflow-documents input[type='file']"
    assert_selector "#component-preview #workflow-documents button", text: "Inspect import"
    assert_selector "#component-preview #workflow-documents button", text: "Create from template"
    assert_selector "#component-preview #workflow-documents a[href='/workflow_demo/documents/export']",
      text: "Export status CSV"

    attach_file "Text or PDF document (up to 1 MB)", Rails.root.join("test/fixtures/files/workflow-demo.txt")
    assert_selector "#component-preview #workflow-documents", text: "1 file selected"
    find("#component-preview #workflow-documents button", text: "Inspect import").click
    wait_for_preview_value("#workflow-documents", "workflow-demo.txt · import")

    assert_selector "#component-preview #workflow-documents", text: "workflow-demo.txt · import"

    assert_no_page_errors
    assert_no_console_errors
  end

  private

  def wait_for_preview_value(selector, expected_text)
    preview_selector = "#component-preview #{selector}"
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script(<<~JS, preview_selector, expected_text)
        document.querySelector(arguments[0])?.textContent.trim().includes(arguments[1]) || false
      JS
    end
  end
end
