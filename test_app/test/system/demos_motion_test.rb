# frozen_string_literal: true

require "application_system_test_case"

# Headline interactions: the numeric pop replay, the staggered toast burst,
# the skeleton reveal, and the shuffle morph — all exercised in a real
# browser with console-error guards.
class DemosMotionTest < ApplicationSystemTestCase
  test "motion tiles animate through their server round trips" do
    visit_demo("motion")

    within("#motion-count") { assert_text "0" }
    click_button "Pop it"
    within("#motion-count") { assert_text "1", wait: 5 }
    assert_selector "#motion-count .motion-enter-scale"

    click_button "Launch a burst"
    assert_selector "#toasts [role='status'][data-toast-duration-ms]", count: 3, wait: 5

    assert_selector "#motion-reveal .animate-pulse", count: 4
    click_button "Reveal"
    assert_text "Go for launch", wait: 5
    assert_selector "#motion-reveal .motion-enter-move-up", count: 4

    order_before = all("[id^='motion-card-']").map { |card| card[:id] }
    click_button "Shuffle"

    # The redirect and Turbo morph are asynchronous. Read the authoritative
    # document in one browser operation so a morph cannot leave us holding a
    # mixed set of old and new element handles under parallel test load.
    order_after = Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time * 2).until do
      order = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("[id^='motion-card-']"), card => card.id)
      JS
      order if order.length == 8 && order != order_before
    end
    refute_equal order_before, order_after, "Shuffle must visibly reorder the cards"
    assert_equal order_before.sort, order_after.sort

    assert_demo_healthy
  end
end
