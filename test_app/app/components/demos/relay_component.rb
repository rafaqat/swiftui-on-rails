# frozen_string_literal: true

module Demos
  # Relay: a split-pane inbox. Thread selection is URL state (?thread=id);
  # sending and archiving are Rails verbs, and archive is also exposed through
  # the semantic swipe-actions contract.
  class RelayComponent < ApplicationComponent
    prop :threads, type: Array, required: true
    prop :selected_thread, type: Object, default: nil
    prop :messages, type: Array, default: []
    prop :archived_count, type: Integer, default: 0

    swift_ui do
      component = @component

      div(id: "relay-app") do
        grid(columns: 2, spacing: 16) do
          inbox_pane
          thread_pane
        end
      end
    end

    private

    def inbox_pane
      vstack(spacing: 8, alignment: :start) do
        hstack(spacing: 8, alignment: :center) do
          text("Inbox").tw("text-xs font-black uppercase tracking-widest text-slate-400")
          span("#{threads.length}").tw("rounded-full bg-slate-200 px-2 py-0.5 text-xs font-black text-slate-600")
          spacer
          text("Route-backed inbox").tw("text-xs font-bold text-slate-400")
        end

        if threads.empty?
          text("Inbox zero. #{archived_count} archived.").tw("text-sm font-bold text-slate-500")
          reset_form
        else
          threads.each { |thread| thread_row(thread) }
        end
      end.tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")
    end

    def thread_row(thread)
      active = selected_thread && selected_thread[:id] == thread[:id]

      archive = swipe_action(
        "Archive",
        action: helpers.demos_relay_archive_path(thread: thread[:id]),
        method: :patch,
        tone: :neutral
      )

      swipe_actions(label: "#{thread[:subject]} actions", actions: [archive]) do
        a(
          id: "relay-thread-#{thread[:id]}",
          href: helpers.demos_relay_path(thread: thread[:id]),
          data: { relay_thread: thread[:id] }
        ) do
          hstack(spacing: 8, alignment: :center) do
            span("").tw("h-2 w-2 rounded-full #{thread[:unread] ? 'bg-sky-500' : 'bg-transparent'}")
            vstack(spacing: 2, alignment: :start) do
              text(thread[:sender]).tw("text-xs font-black uppercase tracking-widest #{active ? 'text-white/70' : 'text-slate-400'}")
              text(thread[:subject]).tw("text-sm font-bold #{active ? 'text-white' : 'text-slate-950'}")
            end
            spacer
            icon("chevron_right", size: 12).tw(active ? "text-white/70" : "text-slate-300")
          end
        end.tw("block w-full rounded-2xl px-4 py-3 transition #{active ? 'bg-slate-950' : 'bg-slate-50 hover:bg-slate-100'}")
      end
    end

    def thread_pane
      vstack(spacing: 12, alignment: :start) do
        if selected_thread
          hstack(spacing: 8, alignment: :center) do
            text(selected_thread[:subject]).tw("text-lg font-black text-slate-950")
            spacer
            archive_form
          end

          vstack(spacing: 8, alignment: :stretch) do
            messages.each { |message| message_bubble(message) }
          end.tw("w-full")

          composer
        else
          text("Select a thread.").tw("text-sm font-bold text-slate-500")
        end
      end.tw("rounded-3xl bg-white p-5 shadow ring-1 ring-slate-900/10")
    end

    def message_bubble(message)
      mine = message[:from] == "You"
      vstack(spacing: 2, alignment: mine ? :end : :start) do
        text(message[:from]).tw("text-[10px] font-black uppercase tracking-widest text-slate-400")
        text(message[:body])
          .tw("max-w-md rounded-2xl px-4 py-2.5 text-sm font-medium leading-6 #{mine ? 'bg-slate-950 text-white' : 'bg-slate-100 text-slate-900'}")
      end.tw("w-full #{mine ? 'items-end' : 'items-start'}")
    end

    def composer
      form(action: helpers.demos_relay_send_path(thread: selected_thread[:id]), method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        hstack(spacing: 8, alignment: :center) do
          input(
            name: "body",
            placeholder: "Reply to #{selected_thread[:sender]}…",
            required: true,
            autocomplete: "off",
            aria: { label: "Message body" }
          ).tw("w-full rounded-full border border-slate-300 px-5 py-2.5 text-sm font-medium focus:border-slate-950 focus:outline-none")
          button("Send", type: "submit")
            .tw("rounded-full bg-slate-950 px-5 py-2.5 text-sm font-black text-white transition hover:bg-slate-800")
        end
      end.tw("w-full")
    end

    def archive_form
      form(action: helpers.demos_relay_archive_path(thread: selected_thread[:id]), method: "post") do
        input(type: "hidden", name: "_method", value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button("Archive", id: "relay-archive-button", type: "submit")
          .tw("rounded-full bg-slate-100 px-4 py-2 text-sm font-black text-slate-600 transition hover:bg-slate-200")
      end
    end

    def reset_form
      form(action: helpers.demos_relay_reset_path, method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button("Restore inbox", type: "submit")
          .tw("rounded-full bg-slate-950 px-5 py-2.5 text-sm font-black text-white transition hover:bg-slate-800")
      end
    end
  end
end
