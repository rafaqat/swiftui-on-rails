# frozen_string_literal: true

require "application_system_test_case"

class ShowcaseCalculatorTest < ApplicationSystemTestCase
  test "calculates with the RPN stack and updates over Turbo" do
    visit showcase_calculator_path

    within "#showcase_calculator" do
      click_button "2"
      assert_selector "[data-stack-register='x'] output", exact_text: "2"
      click_button "ENTER"
      click_button "3"
      assert_selector "[data-stack-register='y'] output", exact_text: "2"
      click_button "+"

      assert_selector "[data-stack-register='x'] output", exact_text: "5"
      assert_selector "[data-testid='calculator-status']", text: /Ready/i
    end

    assert_no_console_errors
  end

  test "supports keyboard activation, scientific functions, and memory registers" do
    visit showcase_calculator_path

    assert_selector "form.calculator__keypad[action='/showcase/calculator/key'][method='post']"
    calculator_key("3").send_keys(:enter)
    assert_selector "[data-stack-register='x'] output", exact_text: "3"
    calculator_key("0").send_keys(:enter)
    assert_selector "[data-stack-register='x'] output", exact_text: "30"
    click_button "sin"
    assert_selector "[data-stack-register='x'] output", text: /0\.5/

    click_button "STO"
    assert_text(/Select register 0–9 to store X/i)
    click_button "4"
    assert_selector "[data-memory-register='4']", exact_text: "0.5"

    calculator_key("clear").send_keys(:enter)
    assert_selector "[data-stack-register='x'] output", exact_text: "0"
    click_button "RCL"
    click_button "4"
    assert_selector "[data-stack-register='x'] output", exact_text: "0.5"

    assert_no_console_errors
  end

  private

  def calculator_key(key)
    find("#showcase_calculator button[name='key'][value='#{key}']")
  end
end
