# frozen_string_literal: true

require "test_helper"

class ModalComponentTest < ViewComponent::TestCase
  test "closed modal renders no dialog" do
    render_inline(ModalComponent.new(open: false, title: "Confirm", close_path: "/close"))

    assert_no_selector "[role='dialog']"
  end

  test "open modal renders its props and slots" do
    component = ModalComponent.new(open: true, title: "Confirm", close_path: "/close")
    component.with_body { "Modal body" }
    component.with_footer { "Modal footer" }

    render_inline(component)

    assert_selector "dialog#modal[role='dialog'][data-sui-dialog][open]"
    assert_selector "#modal-title", text: "Confirm"
    assert_selector "a[aria-label='Close'][href='/close']", text: "Close"
    assert_text "Modal body"
    assert_text "Modal footer"
  end
end
