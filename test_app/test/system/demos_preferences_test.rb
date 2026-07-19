# frozen_string_literal: true

require "application_system_test_case"
require "minitest/mock"

# Headline interaction: a REAL reactive round trip — clicking a theme button
# posts a signed action to swift_ui/actions, the server mutates state, and
# the re-rendered component restyles the preview pane.
class DemosPreferencesTest < ApplicationSystemTestCase
  test "server state round trips restyle the live preview" do
    cache = ActiveSupport::Cache::MemoryStore.new
    SwiftUIRails::RenderIR::PatchBaseline.stub(:cache, cache) do
      visit_demo("preferences")

      assert_selector ".from-sky-500"
      assert_selector "[data-preferences-density]", text: /Comfortable/i
      page.execute_script <<~JAVASCRIPT
        const root = document.querySelector(
          '[data-sui-component="PreferencesComponent"]'
        )
        window.__swiftUIPreferencesRoot = root
        window.__swiftUIPreferencesIncrease = Array.from(root.querySelectorAll('button'))
          .find((button) => button.textContent.trim() === '+')
      JAVASCRIPT

      ember = find_button("Ember")
      page.execute_script("arguments[0].focus()", ember)
      ember.click
      assert_selector ".from-amber-400", wait: 10

      root = find("[data-sui-component='PreferencesComponent']")
      assert_equal "patch", root["data-swift-ui-render-mode"]
      assert_operator root["data-swift-ui-patch-operations"].to_i, :>, 0
      assert page.evaluate_script(<<~JAVASCRIPT), "keyed patch should retain unchanged DOM objects"
        (() => {
          const root = document.querySelector(
            '[data-sui-component="PreferencesComponent"]'
          )
          const increase = Array.from(root.querySelectorAll('button'))
            .find((button) => button.textContent.trim() === '+')
          return root === window.__swiftUIPreferencesRoot &&
            increase === window.__swiftUIPreferencesIncrease
        })()
      JAVASCRIPT
      assert_equal "Ember", page.evaluate_script("document.activeElement.textContent.trim()")

      click_button "+"
      assert_selector "[data-preferences-density]", text: /Spacious/i, wait: 10

      click_button "Hide status badges"
      assert_no_selector "[data-preferences-theme-badge]", wait: 10
      assert_selector "button", text: "Show status badges", wait: 10

      assert_demo_healthy
    end
  end
end
