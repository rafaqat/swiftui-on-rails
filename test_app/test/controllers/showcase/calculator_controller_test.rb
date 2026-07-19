# frozen_string_literal: true

require "test_helper"

module Showcase
  class CalculatorControllerTest < ActionDispatch::IntegrationTest
    test "renders the accessible calculator and all four stack levels" do
      get showcase_calculator_path

      assert_response :success
      assert_select "h1", text: "Scientific thinking, stacked."
      assert_select "[aria-label='RPN scientific calculator']"
      assert_select "[data-stack-register]", count: 4
      assert_select "button[name='key']", minimum: Calculator::ALLOWED_KEYS.length
      assert_select "[data-stack-register='x'] output", text: "0"
    end

    test "persists calculator state across HTML fallback requests" do
      post showcase_calculator_key_path, params: { key: "7" }

      assert_response :see_other
      assert_redirected_to showcase_calculator_path
      follow_redirect!
      assert_select "[data-stack-register='x'] output", text: "7"

      post showcase_calculator_key_path, params: { key: "square" }
      follow_redirect!
      assert_select "[data-stack-register='x'] output", text: "49"
    end

    test "returns a targeted Turbo Stream update" do
      post showcase_calculator_key_path,
           params: { key: "pi" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action='replace'][target='showcase_calculator']"
      assert_select "template [data-stack-register='x'] output", text: /3\.14159/
    end

    test "rejects unknown keys without changing session state" do
      post showcase_calculator_key_path, params: { key: "5" }
      post showcase_calculator_key_path, params: { key: "Kernel.exit!" }

      assert_response :unprocessable_entity

      get showcase_calculator_path
      assert_select "[data-stack-register='x'] output", text: "5"
    end

    test "rejects missing and oversized key parameters" do
      post showcase_calculator_key_path
      assert_response :unprocessable_entity

      post showcase_calculator_key_path, params: { key: "9" * 10_000 }
      assert_response :unprocessable_entity
    end

    test "renders calculation errors as normal calculator state" do
      %w[8 enter 0 /].each do |key|
        post showcase_calculator_key_path,
             params: { key: key },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success
      end

      assert_select ".calculator__status--error", text: "Division by zero"
      assert_select "[data-stack-register='y'] output", text: "8"
    end
  end
end
