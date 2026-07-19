# frozen_string_literal: true

class NavigationPresentationStories < ViewComponent::Storybook::Stories
  include SwiftUIRails::DSL
  include SwiftUIRails::Helpers

  def complete_workflow
    swift_ui do
      div(class: "mx-auto max-w-5xl space-y-8 rounded-3xl bg-slate-50 p-8 text-slate-950") do
        header(class: "space-y-2") do
          text("Route-first navigation & presentation")
            .tw("block text-3xl font-black tracking-tight")
          text("Semantic HTML works first; declared RenderIR commands add modal focus, tabs, popovers, and toolbar keys.")
            .tw("block max-w-3xl text-slate-600")
        end

        navigation_stack(label: "Workspace navigation", class: "rounded-2xl border border-slate-200 bg-white p-3") do
          hstack(spacing: 8, alignment: :center) do
            navigation_link(
              "Dashboard",
              destination: "/rails/stories/navigation_presentation?variant=complete_workflow",
              current: true,
              class: "rounded-lg bg-blue-50 px-3 py-2 text-sm text-blue-700"
            )
            navigation_link(
              "Component lab",
              destination: "/rails/stories",
              class: "rounded-lg px-3 py-2 text-sm text-slate-700 hover:bg-slate-100"
            )
          end
        end

        toolbar(
          id: "format-toolbar",
          label: "Formatting tools",
          class: "rounded-2xl border border-slate-200 bg-white p-3"
        ) do
          toolbar_item(placement: :primary_action, priority: :pinned) do
            button("Bold", type: "button", class: "rounded-lg bg-slate-900 px-3 py-2 text-sm font-bold text-white")
          end
          toolbar_item(placement: :secondary_action) do
            button("Italic", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm")
          end
          toolbar_item(placement: :secondary_action) do
            button("Underline", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm")
          end
        end

        tab_view(id: "project-tabs", label: "Project sections", selection: :overview) do
          tab("Overview", value: :overview) do
            div(class: "rounded-2xl border border-slate-200 bg-white p-6") do
              text("Overview panel").tw("block text-xl font-bold")
              text("The server chooses the initial selection and every panel remains readable without JavaScript.")
                .tw("mt-2 block text-slate-600")
            end
          end
          tab("Activity", value: :activity) do
            div(class: "rounded-2xl border border-slate-200 bg-white p-6") do
              text("Activity panel").tw("block text-xl font-bold")
              text("Arrow keys move between local tabs; Enter follows route-backed tabs.")
                .tw("mt-2 block text-slate-600")
            end
          end
          tab("Audit route", value: :audit, destination: "/rails/stories") do
            text("This fallback content is visible before enhancement.")
          end
        end

        div(class: "flex flex-wrap items-start gap-3") do
          presentation_trigger(
            "Open project sheet",
            target: "project-sheet",
            class: "rounded-xl bg-blue-600 px-4 py-2 font-semibold text-white"
          )
          presentation_trigger(
            "Show save alert",
            target: "save-alert",
            class: "rounded-xl border border-emerald-300 bg-emerald-50 px-4 py-2 font-semibold text-emerald-800"
          )
          presentation_trigger(
            "Confirm deletion",
            target: "delete-confirmation",
            class: "rounded-xl border border-red-300 bg-red-50 px-4 py-2 font-semibold text-red-800"
          )

          popover("Quick actions", id: "quick-actions", class: "rounded-xl border border-slate-300 bg-white px-4 py-2") do
            vstack(spacing: 8, alignment: :start) do
              navigation_link("View activity", destination: "#project-tabs-panel-activity", class: "text-sm text-blue-700")
              navigation_link("Open component lab", destination: "/rails/stories", class: "text-sm text-blue-700")
            end
          end
        end

        sheet("Edit project", id: "project-sheet", presented: false) do
          vstack(spacing: 12, alignment: :start) do
            label("Project name", for_input: "project-name", class: "font-semibold")
            textfield(
              id: "project-name",
              name: "project[name]",
              value: "Apollo",
              class: "w-full rounded-lg border border-slate-300 px-3 py-2"
            )
            text("Saving is intentionally left to a Rails form action.").tw("text-sm text-slate-600")
          end
        end

        alert(
          "Project saved",
          id: "save-alert",
          message: "Apollo is now visible to the whole team.",
          presented: false
        )

        confirmation_dialog(
          "Delete Apollo?",
          id: "delete-confirmation",
          message: "This demo does not perform a mutation.",
          presented: false
        ) do
          button("Delete project", type: "button", class: "rounded-lg bg-red-600 px-4 py-2 font-semibold text-white")
        end
      end
    end
  end

  def adaptive_toolbar
    swift_ui do
      div(class: "mx-auto max-w-5xl space-y-6 rounded-3xl bg-slate-50 p-8 text-slate-950") do
        header(class: "space-y-2") do
          text("Adaptive toolbar overflow")
            .tw("block text-3xl font-black tracking-tight")
          text("Pinned and explicitly visible actions stay put; lower-priority actions move into a native disclosure first.")
            .tw("block max-w-3xl text-slate-600")
        end

        div(
          id: "toolbar-scroll-region",
          class: "rounded-2xl border border-slate-200 bg-white",
          style: "height: 20rem; overflow-y: auto;"
        ) do
          toolbar(
            id: "adaptive-toolbar",
            label: "Document tools",
            overflow_label: "More document actions",
            minimize_on_scroll: true,
            minimize_threshold: 24,
            class: "sticky top-0 z-10 border-b border-slate-200 bg-white p-3",
            style: "box-sizing: border-box; width: 42rem; max-width: 100%;"
          ) do
            toolbar_item(priority: :pinned, style: "inline-size: 7rem;") do
              button(
                "Save",
                type: "button",
                class: "rounded-lg bg-slate-900 px-3 py-2 text-sm font-bold text-white",
                style: "width: 100%;"
              )
            end
            toolbar_item(visibility: :visible, style: "inline-size: 7rem;") do
              button(
                "Status",
                type: "button",
                class: "rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800",
                style: "width: 100%;"
              )
            end
            toolbar_item(priority: :high, style: "inline-size: 7rem;") do
              button("Preview", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm", style: "width: 100%;")
            end
            toolbar_item(style: "inline-size: 7rem;") do
              button("Share", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm", style: "width: 100%;")
            end
            toolbar_item(priority: :low, style: "inline-size: 7rem;") do
              button("Export", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm", style: "width: 100%;")
            end
            toolbar_item(visibility: :overflow, style: "inline-size: 7rem;") do
              button("Advanced", type: "button", class: "rounded-lg border border-slate-300 px-3 py-2 text-sm", style: "width: 100%;")
            end
          end

          div(class: "space-y-4 p-6 text-sm leading-7 text-slate-600") do
            12.times do |index|
              text("Document section #{index + 1}: scroll down to minimize the toolbar, then back up to restore it.")
                .tw("block rounded-lg bg-slate-50 p-3")
            end
          end
        end
      end
    end
  end
end
