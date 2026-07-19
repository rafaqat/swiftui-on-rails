# frozen_string_literal: true

require "test_helper"

module Showcase
  class CalculatorTest < ActiveSupport::TestCase
    test "starts with an empty four-level stack in degree mode" do
      calculator = Calculator.new

      assert_equal [ 0.0, 0.0, 0.0, 0.0 ], calculator.stack
      assert_equal "DEG", calculator.angle_mode
      assert_equal "0", calculator.display(:x)
      assert_equal :ready, calculator.status_kind
    end

    test "performs chained RPN arithmetic with the expected operand order" do
      calculator = Calculator.new

      press(calculator, "12", "enter", "3", "-", "2", "*")

      assert_in_delta 18.0, calculator.stack[0]
      assert_equal "18", calculator.display(:x)
    end

    test "maintains four stack levels and duplicates T when the stack drops" do
      calculator = Calculator.from_state(valid_state(stack: [ 4, 3, 2, 1 ]))

      calculator.press("+")

      assert_equal [ 7.0, 2.0, 1.0, 1.0 ], calculator.stack
    end

    test "ENTER duplicates X while the next entry replaces the duplicate" do
      calculator = Calculator.new

      press(calculator, "2", "enter", "3")

      assert_equal "3", calculator.display(:x)
      assert_equal "2", calculator.display(:y)

      calculator.press("+")
      assert_equal [ 5.0, 0.0, 0.0, 0.0 ], calculator.stack
    end

    test "supports decimal, sign, exponent, and backspace entry" do
      calculator = Calculator.new

      press(calculator, "1", ".", "2", "eex", "3", "chs")
      assert_equal "1.2E-3", calculator.display(:x)

      calculator.press("backspace")
      assert_equal "1.2E-", calculator.display(:x)
      calculator.press("backspace")
      assert_equal "1.2E", calculator.display(:x)
      calculator.press("3")
      calculator.press("enter")

      assert_in_delta 1_200.0, calculator.stack[0]
    end

    test "backspacing an entire pending entry restores the previous X" do
      calculator = Calculator.from_state(valid_state(stack: [ 8, 0, 0, 0 ], lift_on_entry: true))

      press(calculator, "4", "backspace")

      assert_equal "8", calculator.display(:x)
      assert_equal [ 8.0, 0.0, 0.0, 0.0 ], calculator.stack
    end

    test "supports unary scientific operations" do
      calculator = Calculator.new

      press(calculator, "9", "sqrt", "square", "reciprocal")

      assert_in_delta 1.0 / 9.0, calculator.stack[0]

      calculator.press("ln")
      calculator.press("exp")
      assert_in_delta 1.0 / 9.0, calculator.stack[0]

      calculator.press("log10")
      calculator.press("ten_pow")
      assert_in_delta 1.0 / 9.0, calculator.stack[0]
    end

    test "raises Y to X and handles constants" do
      calculator = Calculator.new

      press(calculator, "2", "enter", "8", "pow")
      assert_equal 256.0, calculator.stack[0]

      calculator.press("pi")
      assert_in_delta Math::PI, calculator.stack[0]
      assert_equal 256.0, calculator.stack[1]
    end

    test "evaluates trigonometry in degrees and radians" do
      degrees = Calculator.new
      press(degrees, "3", "0", "sin")
      assert_in_delta 0.5, degrees.stack[0], 1e-12

      press(degrees, "clear", "6", "0", "cos")
      assert_in_delta 0.5, degrees.stack[0], 1e-12

      press(degrees, "clear", "4", "5", "tan")
      assert_in_delta 1.0, degrees.stack[0], 1e-12

      radians = Calculator.new
      press(radians, "pi", "enter", "2", "/", "rad", "sin")
      assert_in_delta 1.0, radians.stack[0], 1e-12
      assert_equal "RAD", radians.angle_mode
    end

    test "rejects a tangent at its singularity" do
      calculator = Calculator.new

      press(calculator, "9", "0", "tan")

      assert_equal "Domain error", calculator.error
      assert_equal "90", calculator.display(:x)
    end

    test "STO and RCL use ten persistent registers" do
      calculator = Calculator.new

      press(calculator, "4", "2", "sto")
      assert_equal "Select register 0–9 to store X", calculator.status_message
      calculator.press("7")
      assert_equal 42.0, calculator.registers["7"]

      press(calculator, "clear", "rcl", "7")
      assert_equal 42.0, calculator.stack[0]
      assert_equal "42", calculator.display_register(7)
    end

    test "swap, drop, and clear apply stack semantics without clearing memory" do
      calculator = Calculator.from_state(valid_state(stack: [ 1, 2, 3, 4 ], registers: { "3" => 9 }))

      calculator.press("swap")
      assert_equal [ 2.0, 1.0, 3.0, 4.0 ], calculator.stack

      calculator.press("drop")
      assert_equal [ 1.0, 3.0, 4.0, 4.0 ], calculator.stack

      calculator.press("clear")
      assert_equal [ 0.0, 0.0, 0.0, 0.0 ], calculator.stack
      assert_equal 9.0, calculator.registers["3"]
    end

    test "division errors are transactional and clear after a successful key" do
      calculator = Calculator.new
      press(calculator, "8", "enter", "0", "/")

      assert_equal "Division by zero", calculator.error
      assert_equal "0", calculator.display(:x)
      assert_equal "8", calculator.display(:y)

      press(calculator, "2", "/")
      assert_nil calculator.error
      assert_equal 4.0, calculator.stack[0]
    end

    test "domain and overflow errors leave the operand available for correction" do
      calculator = Calculator.new
      press(calculator, "9", "chs", "sqrt")

      assert_equal "Domain error", calculator.error
      assert_equal "-9", calculator.display(:x)

      press(calculator, "clear", "1", "eex", "3", "exp")
      assert_equal "Numeric overflow", calculator.error
      assert_equal "1E3", calculator.display(:x)
    end

    test "serializes in-progress input and pending register state" do
      calculator = Calculator.new
      press(calculator, "6", ".", "2", "5")

      restored = Calculator.from_state(calculator.to_h)

      assert_equal calculator.to_h, restored.to_h
      assert restored.entry_active?
      assert_equal "6.25", restored.display(:x)

      restored.press("sto")
      restored = Calculator.from_state(restored.to_h)
      assert_equal "sto", restored.pending_register
      assert_equal "6.25", restored.display(:x)
    end

    test "discards malformed serialized state instead of trusting it" do
      state = valid_state
      state["stack"] = [ Float::INFINITY, 2, 3, 4 ]
      state["error"] = "<script>untrusted</script>"

      calculator = Calculator.from_state(state)

      assert_equal [ 0.0, 0.0, 0.0, 0.0 ], calculator.stack
      assert_nil calculator.error
    end

    test "falls back to defaults for non-hash session data" do
      calculator = Calculator.from_state("obsolete-cookie-value")

      assert_equal [ 0.0, 0.0, 0.0, 0.0 ], calculator.stack
      assert_equal "DEG", calculator.angle_mode
    end

    test "reports division by zero for a zero base and negative power" do
      calculator = Calculator.new

      press(calculator, "0", "enter", "1", "chs", "pow")

      assert_equal "Division by zero", calculator.error
      assert_equal "-1", calculator.display(:x)
      assert_equal "0", calculator.display(:y)
    end

    test "rejects unknown dispatch keys" do
      error = assert_raises(ArgumentError) { Calculator.new.press("__send__") }

      assert_equal "Unknown calculator key", error.message
    end

    private

    def press(calculator, *keys)
      keys.flatten.each do |key|
        value = key.to_s
        if Calculator.valid_key?(value)
          calculator.press(value)
        else
          value.each_char { |character| calculator.press(character) }
        end
      end
    end

    def valid_state(stack: [ 0, 0, 0, 0 ], registers: {}, lift_on_entry: false)
      {
        "version" => Calculator::STATE_VERSION,
        "stack" => stack,
        "registers" => Calculator::DIGITS.each_with_object({}) do |digit, values|
          values[digit] = registers.fetch(digit, 0)
        end,
        "angle_mode" => "DEG",
        "entry" => nil,
        "entry_lifts" => false,
        "lift_on_entry" => lift_on_entry,
        "pending_register" => nil,
        "error" => nil
      }
    end
  end
end
