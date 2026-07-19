# frozen_string_literal: true

module Demos
  # The Flightplan board keeps Rails authoritative. Every move is an ordinary
  # route-backed form and Turbo may progressively replace the returned board.
  class FlightplanComponent < ApplicationComponent
    prop :columns, type: Array, required: true

    swift_ui do
      div(id: "flightplan-board", data: { flightplan_board: true }) do
        grid(columns: 3, spacing: 16) do
          columns.each_with_index { |column, index| board_column(column, index) }
        end

        form(action: helpers.demos_flightplan_reset_path, method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button("Reset board", type: "submit")
            .tw("mt-6 rounded-full bg-white px-5 py-2.5 text-sm font-black text-slate-500 shadow ring-1 ring-slate-900/10 transition hover:text-slate-950")
        end
      end
    end

    private

    def board_column(column, index)
      at_limit = column[:wip_limit] && column[:cards].length >= column[:wip_limit]

      vstack(spacing: 12, alignment: :start) do
        hstack(spacing: 8, alignment: :center) do
          text(column[:name]).tw("text-sm font-black uppercase tracking-widest text-slate-500")
          span(count_label(column))
            .tw("rounded-full px-2 py-0.5 text-xs font-black #{at_limit ? 'bg-rose-100 text-rose-800' : 'bg-slate-200 text-slate-600'}")
          spacer
        end

        vstack(spacing: 8, alignment: :stretch) do
          column[:cards].each do |card|
            render KanbanCardComponent.new(
              title: card[:title],
              card_key: card[:key],
              topic: card[:tag],
              priority: card[:priority],
              move_left_path: adjacent_move_path(card, index, -1),
              move_right_path: adjacent_move_path(card, index, +1)
            )
          end
        end
          .tw("min-h-40 rounded-2xl bg-slate-100/80 p-3")
          .data(flightplan_column: column[:id])
      end
        .tw("rounded-3xl bg-white/60 p-4 ring-1 ring-slate-900/5")
    end

    def count_label(column)
      column[:wip_limit] ? "#{column[:cards].length}/#{column[:wip_limit]}" : column[:cards].length.to_s
    end

    def adjacent_move_path(card, column_index, offset)
      target = column_index + offset
      return nil if target.negative? || target >= columns.length

      helpers.demos_flightplan_card_move_path(card: card[:key], to: columns[target][:id])
    end
  end
end
