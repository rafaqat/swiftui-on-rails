# frozen_string_literal: true

require "application_system_test_case"

class EnvironmentInteractionTest < ApplicationSystemTestCase
  test "lifecycle focus and keyboard activation use real browser semantics" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      const element = document.createElement("div")
      element.id = "interaction-focus-fixture"
      element.tabIndex = 0
      element.setAttribute("role", "button")
      element.dataset.suiLifecycle = "1"
      element.dataset.suiLifecycleId = "browser-test"
      element.dataset.suiFocus = JSON.stringify({ key: "field", value: "email", active: true })
      element.dataset.suiKeyboardActivate = "1"
      element.dataset.suiTap = "1"
      element.dataset.suiKeypress = JSON.stringify({
        keys: ["Enter"], modifiers: ["shift"], phase: "keydown", scope: "element", preventDefault: false
      })
      element.textContent = "Activate"
      element.addEventListener("swift-ui-appear", () => { element.dataset.appeared = "true" })
      element.addEventListener("swift-ui-focus-change", (event) => {
        element.dataset.focusDetail = JSON.stringify(event.detail)
      })
      element.addEventListener("swift-ui-key-press", (event) => {
        element.dataset.keyDetail = JSON.stringify(event.detail)
      })
      element.addEventListener("click", () => {
        element.dataset.clickCount = String(Number(element.dataset.clickCount || 0) + 1)
      })
      document.body.appendChild(element)
    JAVASCRIPT

    assert_selector "#interaction-focus-fixture[data-appeared='true'][data-sui-focus-state='focused']"
    assert_equal "interaction-focus-fixture", page.evaluate_script("document.activeElement.id")

    find("#interaction-focus-fixture").send_keys([ :shift, :enter ])

    assert_selector "#interaction-focus-fixture[data-click-count='1'][data-key-detail]"
    focus_detail = JSON.parse(find("#interaction-focus-fixture")["data-focus-detail"])
    key_detail = JSON.parse(find("#interaction-focus-fixture")["data-key-detail"])
    assert_equal({ "key" => "field", "value" => "email", "focused" => true }, focus_detail)
    assert_equal "Enter", key_detail.fetch("key")
    assert key_detail.fetch("shiftKey")
    assert_no_console_errors
  end

  test "long press and drag emit bounded value-producing events" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      const element = document.createElement("div")
      element.id = "interaction-gesture-fixture"
      element.dataset.suiKeyboardActivate = "1"
      element.dataset.suiTap = "1"
      element.dataset.suiLongPress = JSON.stringify({ duration: 200, distance: 10 })
      element.dataset.suiDrag = JSON.stringify({ distance: 5, axis: "horizontal" })
      element.textContent = "Gesture target"
      element.addEventListener("swift-ui-long-press", (event) => {
        element.dataset.longPressDetail = JSON.stringify(event.detail)
      })
      element.addEventListener("swift-ui-drag-end", (event) => {
        element.dataset.dragDetail = JSON.stringify(event.detail)
      })
      element.addEventListener("click", () => {
        element.dataset.acceptedClickCount = String(Number(element.dataset.acceptedClickCount || 0) + 1)
      })
      document.body.appendChild(element)
    JAVASCRIPT

    assert_selector "#interaction-gesture-fixture[data-sui-long-press][data-sui-drag]"
    page.execute_script <<~JAVASCRIPT
      document.getElementById("interaction-gesture-fixture").dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true, pointerId: 1, isPrimary: true, pointerType: "mouse", clientX: 10, clientY: 10
      }))
    JAVASCRIPT
    assert_selector "#interaction-gesture-fixture[data-long-press-detail]"
    page.execute_script <<~JAVASCRIPT
      const element = document.getElementById("interaction-gesture-fixture")
      element.dispatchEvent(new PointerEvent("pointercancel", {
        bubbles: true, pointerId: 1, isPrimary: true, pointerType: "mouse", clientX: 10, clientY: 10
      }))
      const unrelatedClick = new MouseEvent("click", { bubbles: true, cancelable: true, view: window })
      element.dataset.unrelatedClickAccepted = String(element.dispatchEvent(unrelatedClick))
      element.dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true, pointerId: 2, isPrimary: true, pointerType: "mouse", clientX: 0, clientY: 0
      }))
      element.dispatchEvent(new PointerEvent("pointermove", {
        bubbles: true, cancelable: true, pointerId: 2, isPrimary: true, pointerType: "mouse", clientX: 30, clientY: 15
      }))
      element.dispatchEvent(new PointerEvent("pointerup", {
        bubbles: true, pointerId: 2, isPrimary: true, pointerType: "mouse", clientX: 40, clientY: 20
      }))
      element.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" }))
      element.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, cancelable: true, key: "Enter" }))
    JAVASCRIPT
    assert_selector "#interaction-gesture-fixture[data-drag-detail][data-unrelated-click-accepted='true'][data-accepted-click-count='2']"
    long_press = JSON.parse(find("#interaction-gesture-fixture")["data-long-press-detail"])
    drag = JSON.parse(find("#interaction-gesture-fixture")["data-drag-detail"])
    assert_equal 200, long_press.fetch("duration")
    assert_equal "mouse", long_press.fetch("pointerType")
    assert_equal({ "x" => 40, "y" => 0 }, drag.fetch("translation"))
    assert_no_console_errors
  end

  test "task fetch reports lifecycle state while preserving initial content" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      const element = document.createElement("div")
      element.id = "interaction-task-fixture"
      element.textContent = "Server fallback"
      element.dataset.suiLifecycle = "1"
      element.dataset.suiLifecycleId = "task-test"
      element.dataset.suiTask = JSON.stringify({ url: "/", method: "GET", trigger: "appear", response: "event" })
      element.addEventListener("swift-ui-task-success", (event) => {
        element.dataset.taskResultKind = event.detail.result.kind
      })
      document.body.appendChild(element)
    JAVASCRIPT

    assert_selector "#interaction-task-fixture[data-sui-task-state='success'][data-task-result-kind='html']", text: "Server fallback"
    assert_no_selector "#interaction-task-fixture[aria-busy]"
    assert_no_console_errors
  end
end
