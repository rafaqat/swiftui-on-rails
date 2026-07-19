# frozen_string_literal: true

module Showcase
  # A small, deterministic four-level RPN calculator. The object has no Rails
  # dependencies so it can be exercised independently and safely serialized to
  # a session between requests.
  class Calculator
    STACK_SIZE = 4
    DIGITS = ("0".."9").to_a.freeze
    ANGLE_MODES = %w[DEG RAD].freeze
    REGISTER_OPERATIONS = %w[sto rcl].freeze
    ERROR_MESSAGES = [
      "Division by zero",
      "Domain error",
      "Numeric overflow",
      "Invalid number",
      "Entry is too long"
    ].freeze
    ALLOWED_KEYS = (
      DIGITS + %w[
        . enter chs eex backspace + - * / sqrt square pow reciprocal ln log10
        exp ten_pow sin cos tan deg rad pi swap drop clear sto rcl
      ]
    ).freeze

    MAX_ENTRY_LENGTH = 28
    STATE_VERSION = 1

    class CalculationError < StandardError; end

    attr_reader :angle_mode, :error, :pending_register

    def initialize(state = nil)
      reset_to_defaults
      restore_state(state) unless state.nil?
    rescue TypeError, ArgumentError
      reset_to_defaults
    end

    def self.from_state(state)
      new(state)
    end

    def self.valid_key?(key)
      ALLOWED_KEYS.include?(key.to_s)
    end

    def press(key)
      key = key.to_s
      raise ArgumentError, "Unknown calculator key" unless self.class.valid_key?(key)

      snapshot = to_h
      @error = nil

      begin
        if @pending_register && DIGITS.include?(key)
          apply_register(@pending_register, key)
        else
          @pending_register = nil unless REGISTER_OPERATIONS.include?(key)
          dispatch(key)
        end
      rescue CalculationError => exception
        restore_state(snapshot)
        @error = exception.message
      rescue Math::DomainError, FloatDomainError, RangeError, ZeroDivisionError
        restore_state(snapshot)
        @error = "Domain error"
      end

      self
    end

    def stack
      @stack.dup
    end

    def registers
      @registers.dup
    end

    def entry_active?
      !@entry.nil?
    end

    def display(slot)
      index = { x: 0, y: 1, z: 2, t: 3 }.fetch(slot.to_sym)
      return @entry.tr("e", "E") if index.zero? && entry_active?

      values = display_stack
      format_number(values.fetch(index))
    end

    def display_register(index)
      format_number(@registers.fetch(index.to_s))
    end

    def status_message
      return @error if @error
      return "Select register 0–9 to #{@pending_register == 'sto' ? 'store X' : 'recall'}" if @pending_register

      "Ready · four-level RPN stack"
    end

    def status_kind
      return :error if @error
      return :pending if @pending_register

      :ready
    end

    def to_h
      {
        "version" => STATE_VERSION,
        "stack" => @stack.dup,
        "registers" => @registers.dup,
        "angle_mode" => @angle_mode,
        "entry" => @entry,
        "entry_lifts" => @entry_lifts,
        "lift_on_entry" => @lift_on_entry,
        "pending_register" => @pending_register,
        "error" => @error
      }
    end

    private

    def dispatch(key)
      case key
      when *DIGITS then append_digit(key)
      when "." then append_decimal
      when "enter" then enter
      when "chs" then change_sign
      when "eex" then begin_exponent
      when "backspace" then backspace
      when "+" then binary_operation { |left, right| left + right }
      when "-" then binary_operation { |left, right| left - right }
      when "*" then binary_operation { |left, right| left * right }
      when "/" then divide
      when "sqrt" then square_root
      when "square" then unary_operation { |value| value * value }
      when "pow" then power
      when "reciprocal" then reciprocal
      when "ln" then logarithm(:natural)
      when "log10" then logarithm(:base_ten)
      when "exp" then unary_operation { |value| Math.exp(value) }
      when "ten_pow" then unary_operation { |value| 10.0**value }
      when "sin" then trigonometric(:sin)
      when "cos" then trigonometric(:cos)
      when "tan" then tangent
      when "deg" then @angle_mode = "DEG"
      when "rad" then @angle_mode = "RAD"
      when "pi" then enter_constant(Math::PI)
      when "swap" then swap
      when "drop" then drop
      when "clear" then clear_stack
      when "sto", "rcl" then begin_register_operation(key)
      end
    end

    def append_digit(digit)
      start_entry("0") unless entry_active?
      return if @entry == "0" && digit == "0"

      if @entry == "0"
        @entry = digit
      elsif @entry == "-0"
        @entry = "-#{digit}"
      else
        append_to_entry(digit)
      end
    end

    def append_decimal
      start_entry("0") unless entry_active?
      return if @entry.include?("e") || @entry.include?(".")

      append_to_entry(".")
    end

    def begin_exponent
      if entry_active?
        return if @entry.include?("e")

        append_to_entry("e")
      else
        current_value = format_input(@stack.first)
        @entry = current_value.include?("e") ? current_value : "#{current_value}e"
        @entry_lifts = false
        @lift_on_entry = false
      end
    end

    def change_sign
      if entry_active?
        mantissa, exponent = @entry.split("e", 2)
        if exponent
          exponent = exponent.start_with?("-") ? exponent.delete_prefix("-") : "-#{exponent.delete_prefix('+')}"
          @entry = "#{mantissa}e#{exponent}"
        else
          @entry = mantissa.start_with?("-") ? mantissa.delete_prefix("-") : "-#{mantissa}"
        end
      else
        unary_operation { |value| -value }
      end
    end

    def backspace
      unless entry_active?
        @stack[0] = 0.0
        @lift_on_entry = false
        return
      end

      original_lift = @entry_lifts
      @entry = @entry[0...-1]
      if @entry.empty? || @entry == "-"
        @entry = nil
        @entry_lifts = false
        @lift_on_entry = original_lift
      end
    end

    def enter
      commit_entry
      x, y, z, = @stack
      @stack = [ x, x, y, z ]
      @lift_on_entry = false
    end

    def divide
      binary_operation do |left, right|
        raise CalculationError, "Division by zero" if right.zero?

        left / right
      end
    end

    def square_root
      unary_operation do |value|
        raise CalculationError, "Domain error" if value.negative?

        Math.sqrt(value)
      end
    end

    def power
      binary_operation do |base, exponent|
        raise CalculationError, "Division by zero" if base.zero? && exponent.negative?

        if base.negative? && exponent != exponent.truncate
          raise CalculationError, "Domain error"
        end

        base**exponent
      end
    end

    def reciprocal
      unary_operation do |value|
        raise CalculationError, "Division by zero" if value.zero?

        1.0 / value
      end
    end

    def logarithm(kind)
      unary_operation do |value|
        raise CalculationError, "Domain error" unless value.positive?

        kind == :natural ? Math.log(value) : Math.log10(value)
      end
    end

    def trigonometric(operation)
      unary_operation do |value|
        radians = angle_to_radians(value)
        result = operation == :sin ? Math.sin(radians) : Math.cos(radians)
        normalize_trigonometric(result)
      end
    end

    def tangent
      unary_operation do |value|
        radians = angle_to_radians(value)
        raise CalculationError, "Domain error" if Math.cos(radians).abs < 1e-14

        normalize_trigonometric(Math.tan(radians))
      end
    end

    def swap
      commit_entry
      @stack[0], @stack[1] = @stack[1], @stack[0]
      @lift_on_entry = true
    end

    def drop
      commit_entry
      _, y, z, t = @stack
      @stack = [ y, z, t, t ]
      @lift_on_entry = true
    end

    def clear_stack
      @stack = Array.new(STACK_SIZE, 0.0)
      @entry = nil
      @entry_lifts = false
      @lift_on_entry = false
      @pending_register = nil
      @error = nil
    end

    def begin_register_operation(operation)
      commit_entry
      @pending_register = operation
    end

    def apply_register(operation, register)
      if operation == "sto"
        @registers[register] = @stack.first
        @lift_on_entry = true
      else
        enter_constant(@registers.fetch(register))
      end
      @pending_register = nil
    end

    def enter_constant(value)
      if entry_active?
        commit_entry
        @lift_on_entry = true
      end

      lift_stack if @lift_on_entry
      @stack[0] = value
      @lift_on_entry = true
    end

    def unary_operation
      commit_entry
      @stack[0] = finite_number!(yield(@stack.first))
      @lift_on_entry = true
    end

    def binary_operation
      commit_entry
      x, y, z, t = @stack
      result = finite_number!(yield(y, x))
      @stack = [ result, z, t, t ]
      @lift_on_entry = true
    end

    def commit_entry
      return unless entry_active?

      value = parse_entry(@entry)
      lift_stack if @entry_lifts
      @stack[0] = value
      @entry = nil
      @entry_lifts = false
      @lift_on_entry = false
    end

    def start_entry(initial)
      @entry = initial
      @entry_lifts = @lift_on_entry
      @lift_on_entry = false
    end

    def append_to_entry(character)
      raise CalculationError, "Entry is too long" if @entry.length >= MAX_ENTRY_LENGTH

      @entry += character
    end

    def parse_entry(entry)
      value = Float(entry)
      finite_number!(value, "Invalid number")
    rescue ArgumentError
      raise CalculationError, "Invalid number"
    end

    def lift_stack
      x, y, z, = @stack
      @stack = [ 0.0, x, y, z ]
    end

    def display_stack
      return @stack unless entry_active? && @entry_lifts

      [ @stack[0], @stack[0], @stack[1], @stack[2] ]
    end

    def angle_to_radians(value)
      @angle_mode == "DEG" ? value * Math::PI / 180.0 : value
    end

    def normalize_trigonometric(value)
      value.abs < 1e-14 ? 0.0 : value
    end

    def finite_number!(value, non_numeric_message = "Numeric overflow")
      number = Float(value)
      raise CalculationError, "Numeric overflow" unless number.finite?

      number
    rescue TypeError, ArgumentError
      raise CalculationError, non_numeric_message
    end

    def format_number(value)
      return "0" if value.zero?

      format("%.12g", value).sub("e+", "e").tr("e", "E")
    end

    def format_input(value)
      format("%.15g", value).sub("e+", "e")
    end

    def restore_state(state)
      raise TypeError unless state.respond_to?(:to_h)

      state = stringify_keys(state.to_h)
      raise TypeError unless state["version"] == STATE_VERSION

      stack = validate_number_array(state["stack"], STACK_SIZE)
      registers = validate_registers(state["registers"])
      mode = state["angle_mode"].to_s
      raise TypeError unless ANGLE_MODES.include?(mode)

      entry = validate_entry(state["entry"])
      pending = state["pending_register"]&.to_s
      raise TypeError unless pending.nil? || REGISTER_OPERATIONS.include?(pending)

      error = state["error"]&.to_s
      raise TypeError unless error.nil? || ERROR_MESSAGES.include?(error)

      @stack = stack
      @registers = registers
      @angle_mode = mode
      @entry = entry
      @entry_lifts = boolean_value(state["entry_lifts"])
      @lift_on_entry = boolean_value(state["lift_on_entry"])
      @pending_register = pending
      @error = error
    end

    def validate_number_array(value, length)
      raise TypeError unless value.is_a?(Array) && value.length == length

      value.map { |number| finite_state_number(number) }
    end

    def validate_registers(value)
      raise TypeError unless value.respond_to?(:to_h)

      value = stringify_keys(value.to_h)
      raise TypeError unless value.keys.sort == DIGITS

      DIGITS.each_with_object({}) do |digit, registers|
        registers[digit] = finite_state_number(value.fetch(digit))
      end
    end

    def validate_entry(value)
      return if value.nil?

      entry = value.to_s
      valid = entry.length <= MAX_ENTRY_LENGTH && entry.match?(/\A-?\d+(?:\.\d*)?(?:e[+-]?\d*)?\z/)
      raise TypeError unless valid

      entry
    end

    def finite_state_number(value)
      number = Float(value)
      raise TypeError unless number.finite?

      number
    rescue ArgumentError
      raise TypeError
    end

    def boolean_value(value)
      raise TypeError unless value == true || value == false

      value
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), copy| copy[key.to_s] = value }
    end

    def reset_to_defaults
      @stack = Array.new(STACK_SIZE, 0.0)
      @registers = DIGITS.each_with_object({}) { |digit, registers| registers[digit] = 0.0 }
      @angle_mode = "DEG"
      @entry = nil
      @entry_lifts = false
      @lift_on_entry = false
      @pending_register = nil
      @error = nil
    end
  end
end
