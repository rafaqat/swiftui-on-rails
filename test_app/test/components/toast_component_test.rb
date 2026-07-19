# frozen_string_literal: true

require "test_helper"

class ToastComponentTest < ViewComponent::TestCase
  def test_renders_message_with_variant_style_and_signed_dismiss_action
    render_inline(ToastComponent.new(message: "Flight plan updated.", variant: "success"))

    assert_text "Flight plan updated."
    assert_selector "[role='status'][data-toast-duration-ms='5000']"
    assert_selector ".bg-emerald-600"
    assert_selector "button[aria-label='Dismiss notification'][data-sui-actions]"
  end

  def test_unknown_variant_falls_back_to_info
    render_inline(ToastComponent.new(message: "Hello", variant: "constantize"))

    assert_selector ".bg-slate-950"
  end

  def test_duration_is_configurable
    render_inline(ToastComponent.new(message: "Slow", duration: 10_000))

    assert_selector "[data-toast-duration-ms='10000']"
  end
end
