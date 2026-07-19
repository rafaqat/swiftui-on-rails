# frozen_string_literal: true

class Wwdc26WorkflowsStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  ITEMS = {
    "research" => ["Research", "Customer interviews and evidence"],
    "design" => ["Design", "Interaction and accessibility review"],
    "build" => ["Build", "Rails implementation and verification"],
    "release" => ["Release", "UAT, audit, and rollout"]
  }.freeze

  def portable_workflows
    controller = view_context.controller
    session = controller.session
    order = Array(session[:workflow_demo_order]).map(&:to_s)
    order = ITEMS.keys unless order.sort == ITEMS.keys.sort
    message_status = session[:workflow_demo_message_status]
    document_status = session[:workflow_demo_document_status]

    swift_ui do
      div(class: "min-h-screen bg-slate-950 p-6 text-slate-100 sm:p-10") do
        div(class: "mx-auto max-w-6xl space-y-8") do
          header(class: "max-w-3xl space-y-3") do
            text("WWDC26 · WEB EQUIVALENTS").tw("block text-xs font-black tracking-[0.3em] text-cyan-300")
            h1("Portable workflows, Rails authority", class: "text-4xl font-black tracking-tight text-white sm:text-5xl")
            p(
              "Stable-key moves, swipe conveniences, and document provenance work without JavaScript. Declared RenderIR commands add drag, pointer swipe, and progress reporting without becoming a second state store.",
              class: "text-lg leading-8 text-slate-300"
            )
          end

          section(id: "workflow-reorder", class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
            h2("Arbitrary-layout reordering", class: "text-2xl font-black text-white")
            p(
              "Move buttons are the universal interaction. Dragging submits the same stable-key form and the server returns the authoritative order.",
              class: "mb-5 mt-2 text-sm leading-6 text-slate-300"
            )
            reorderable_collection(
              items: order.map { |key| { key: key, title: ITEMS.fetch(key).first, detail: ITEMS.fetch(key).last } },
              key: :key,
              item_label: :title,
              move_path: "/workflow_demo/reorder",
              label: "Delivery stages",
              id: "delivery-order",
              layout: :grid,
              columns: 2,
              method: :patch,
              class: "gap-4"
            ) do |item, index|
              div(class: "rounded-2xl border border-white/10 bg-slate-900 p-4") do
                text("#{index + 1}").tw("mb-3 inline-flex h-8 w-8 items-center justify-center rounded-full bg-cyan-300 font-black text-slate-950")
                text(item.fetch(:title)).tw("block text-lg font-black text-white")
                text(item.fetch(:detail)).tw("mt-1 block text-sm text-slate-400")
              end
            end
          end

          section(id: "workflow-swipe", class: "rounded-3xl border border-white/10 bg-white/5 p-6") do
            h2("Swipe actions with visible alternatives", class: "text-2xl font-black text-white")
            p(
              "A trailing pointer swipe announces the action rail; it never performs a mutation. The Archive and Delete forms stay visible and keyboard-focusable.",
              class: "mb-5 mt-2 text-sm leading-6 text-slate-300"
            )
            badge(message_status, tone: :success, announce: true, class: "mb-4") if message_status.present?
            div(class: "space-y-3") do
              [
                ["roadmap", "Roadmap review", "Ari · 12 minutes ago"],
                ["incident", "Incident follow-up", "Operations · yesterday"]
              ].each do |key, subject, detail|
                archive = swipe_action(
                  "Archive",
                  action: "/workflow_demo/messages/#{key}/archive",
                  method: :patch,
                  tone: :accent,
                  class: "rounded-xl px-4 py-2 font-bold"
                )
                destroy = swipe_action(
                  "Delete",
                  action: "/workflow_demo/messages/#{key}/delete",
                  method: :delete,
                  tone: :destructive,
                  class: "rounded-xl px-4 py-2 font-bold"
                )
                swipe_actions(
                  label: subject,
                  actions: [archive, destroy],
                  edge: :trailing,
                  class: "flex flex-col gap-3 rounded-2xl border border-white/10 bg-slate-900 p-4 sm:flex-row sm:items-center sm:justify-between"
                ) do
                  div do
                    text(subject).tw("block font-black text-white")
                    text(detail).tw("mt-1 block text-sm text-slate-400")
                  end
                end
              end
            end
          end

          document_workflow(
            label: "Document workflow",
            id: "workflow-documents",
            class: "rounded-3xl border border-white/10 bg-white/5 p-6"
          ) do
            h2("Documents with signed provenance", class: "text-2xl font-black text-white")
            p(
              "Import is a bounded multipart form, creation context is signed and expiring, and export is a normal streaming download link.",
              class: "mb-5 mt-2 text-sm leading-6 text-slate-300"
            )
            if document_status.present?
              badge(
                "#{document_status.fetch('filename', document_status[:filename])} · #{document_status.fetch('source', document_status[:source])}",
                tone: :success,
                announce: true,
                class: "mb-4"
              )
            end
            div(class: "grid gap-4 lg:grid-cols-2") do
              document_import(
                action: "/workflow_demo/documents/import",
                accept: [".txt", "text/plain", ".pdf", "application/pdf"],
                max_bytes: 1.megabyte,
                source: :import,
                metadata: { surface: "storybook", workflow: "portable" },
                label: "Text or PDF document (up to 1 MB)",
                submit_label: "Inspect import",
                id: "workflow-document-import",
                class: "space-y-3 rounded-2xl border border-white/10 bg-slate-900 p-5"
              ) do
                text("Nothing is stored by this demo; the server validates metadata and reports the file envelope.")
                  .tw("block text-sm leading-6 text-slate-400")
              end
              div(class: "space-y-3 rounded-2xl border border-white/10 bg-slate-900 p-5") do
                text("Creation and export").tw("block text-lg font-black text-white")
                text("Both actions stay native: a CSRF form for creation and a same-origin GET for streaming bytes.")
                  .tw("block text-sm leading-6 text-slate-400")
                document_creation_action(
                  "Create from template",
                  action: "/workflow_demo/documents",
                  source: :template,
                  metadata: { template_id: "weekly-status", surface: "storybook" },
                  class: "inline-block"
                )
                document_export(
                  "Export status CSV",
                  destination: "/workflow_demo/documents/export",
                  filename: "workflow-status.csv",
                  content_type: "text/csv",
                  class: "inline-flex rounded-xl border border-cyan-300 px-4 py-2 font-bold text-cyan-200"
                )
              end
            end
          end
        end
      end
    end
  end
end
