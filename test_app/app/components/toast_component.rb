# frozen_string_literal: true

# A server-owned notification. Turbo Streams may append it and its dismiss
# action is a signed Ruby round trip handled by the shared protocol runtime.
class ToastComponent < ApplicationComponent
  VARIANT_STYLES = {
    "info" => { classes: "bg-slate-950 text-white", glyph: "info" },
    "success" => { classes: "bg-emerald-600 text-white", glyph: "check" },
    "warning" => { classes: "bg-amber-500 text-slate-950", glyph: "warning" },
    "error" => { classes: "bg-rose-600 text-white", glyph: "x" }
  }.freeze

  prop :message, type: String, required: true
  prop :variant, type: String, default: "info"
  prop :duration, type: Integer, default: 5000
  # Staggers the entrance animation when several toasts arrive together.
  prop :enter_delay, type: Integer, default: 0

  state :visible, true

  swift_ui do
    style = VARIANT_STYLES.fetch(variant, VARIANT_STYLES["info"])

    div(
      role: "status",
      hidden: !visible,
      data: { toast_duration_ms: duration }
    ) do
      hstack(spacing: 8, alignment: :center) do
        icon(style.fetch(:glyph), size: 14)
        text(message).tw("text-sm font-bold")
        spacer
        dismiss = button(type: "button", aria: { label: "Dismiss notification" }) do
          icon("x", size: 12)
        end.tw("rounded-full p-1 opacity-70 transition hover:opacity-100")
        dismiss.on_click { @component.visible = false }
      end
    end
      .tw("pointer-events-auto w-80 rounded-2xl px-4 py-3 shadow-2xl #{style.fetch(:classes)}")
      .transition(insertion: :move_up, removal: :opacity)
      .then { |toast| enter_delay.positive? ? toast.style("animation-delay: #{enter_delay}ms") : toast }
  end
end
