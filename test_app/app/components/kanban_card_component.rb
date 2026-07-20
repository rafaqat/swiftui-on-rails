# frozen_string_literal: true

# A server-owned kanban card. Its move forms are the pointer and keyboard path,
# so Rails remains the only board-state authority.
class KanbanCardComponent < ApplicationComponent
  PRIORITY_STYLES = {
    "low" => "bg-slate-100 text-slate-600",
    "medium" => "bg-amber-100 text-amber-800",
    "high" => "bg-rose-100 text-rose-800"
  }.freeze

  TAG_STYLES = {
    "guidance" => "text-sky-700",
    "systems" => "text-violet-700",
    "ops" => "text-emerald-700",
    "comms" => "text-amber-700"
  }.freeze

  UNSAFE_PATH_CHARACTERS = /[\x00-\x20\x7f]/

  prop :title, type: String, required: true
  prop :card_key, type: String, default: "sample-card"
  prop :topic, type: String, default: "ops"
  prop :priority, type: String, default: "medium"
  prop :move_left_path, type: String, default: nil
  prop :move_right_path, type: String, default: nil

  swift_ui do
    div(data: { flightplan_card_key: card_key }) do
      hstack(spacing: 8, alignment: :center) do
        span(priority.capitalize)
          .tw("rounded-full px-2 py-0.5 text-[10px] font-black uppercase tracking-widest #{PRIORITY_STYLES.fetch(priority, PRIORITY_STYLES['medium'])}")
        spacer
        span("##{topic}").tw("text-xs font-black #{TAG_STYLES.fetch(topic, 'text-slate-500')}")
      end

      text(title).tw("mt-2 text-sm font-bold leading-5 text-slate-950")

      if move_left_path || move_right_path
        hstack(spacing: 4, alignment: :center) do
          move_button(move_left_path, "chevron_left", "Move #{title} to the previous column") if move_left_path
          spacer
          move_button(move_right_path, "chevron_right", "Move #{title} to the next column") if move_right_path
        end.tw("mt-3 opacity-0 transition group-hover:opacity-100 focus-within:opacity-100")
      end
    end
      .tw("group rounded-2xl bg-white p-4 shadow ring-1 ring-slate-900/10 transition hover:shadow-md")
  end

  private

  # The move forms POST a CSRF token, so their action must be an
  # application-relative path — never an absolute or protocol-relative URL that
  # could carry the token to another origin. Mirrors the shell's current_path
  # validation.
  def validate_props!
    super

    [move_left_path, move_right_path].compact.each do |path|
      unless path.start_with?("/") &&
          !path.start_with?("//") &&
          !path.match?(UNSAFE_PATH_CHARACTERS)
        raise ArgumentError, "move paths must be application-relative"
      end
    end
  end

  def move_button(path, glyph, label)
    form(action: path, method: "post") do
      input(type: "hidden", name: "_method", value: "patch")
      input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
      button(type: "submit", aria: { label: label }) do
        icon(glyph, size: 14)
      end.tw("rounded-full bg-slate-100 px-2.5 py-1 text-slate-600 transition hover:bg-slate-950 hover:text-white")
    end
  end
end
