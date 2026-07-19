# Navigation and presentation

SwiftUI Rails preserves the portable intent of SwiftUI navigation and presentation while keeping Rails and the browser authoritative. It does not emulate `NavigationPath`, native view-controller stacks, or an Apple window scene. Application behavior remains Ruby/RenderIR; the gem-owned DOM runtime implements the bounded browser mechanics described here without application controllers or JavaScript callbacks.

## NavigationStack and NavigationLink

`navigation_stack` renders a labelled `nav`; `navigation_link` renders a validated anchor. Rails routes, Turbo, browser history, and normal link behaviors remain available.

```ruby
navigation_stack(label: "Account") do
  navigation_link("Profile", destination: profile_path, current: request.path == profile_path)
  navigation_link("Security", destination: security_path, turbo_frame: "account")
end
```

Use `replace: true` only when the visit should replace the current browser-history entry. Unsafe URL schemes fail closed. Automatic `aria-current="page"` matching only considers same-origin route paths; fragments and protocol-relative external URLs are never announced as the current page.

## TabView

Local tabs use hash links as their HTML fallback. Before the framework runtime connects, every panel remains readable. A semantic tab command then applies visibility, roving focus, arrow keys, Home, and End behavior.

```ruby
tab_view(id: "project-tabs", label: "Project sections", selection: :overview) do
  tab("Overview", value: :overview) { project_overview }
  tab("Activity", value: :activity) { project_activity }
  tab("Audit", value: :audit, destination: project_audit_path) { audit_fallback }
end
```

A tab with `destination:` is route-backed. Arrow keys can focus it, while Enter follows its real link and lets Rails choose the next selection.

The panel hash is the portable navigation state for local tabs. A matching hash on the initial request selects that panel after enhancement, pointer and keyboard selection push a browser-history entry, and Back/Forward restore the matching selection. A hash is honored only when it names the panel owned by that exact tab view; malformed hashes, nested tab views, and missing panels fall back to the server-selected tab without trapping the real anchor. This deliberately does not create a second `NavigationPath` beside Rails and browser history.

## Sheets, alerts, and confirmation dialogs

These builders render native `dialog` elements. An open dialog is useful as non-modal HTML when JavaScript is unavailable; the framework's allowlisted presentation command upgrades it with `showModal()`, focus isolation, Escape handling, backdrop dismissal, and focus restoration.

```ruby
presentation_trigger("Edit", target: "edit-sheet", fallback: edit_project_path(sheet: true))

sheet("Edit project", id: "edit-sheet", presented: params[:sheet].present?) do
  render ProjectFormComponent.new(project: @project)
end

alert("Saved", message: "The project is live", presented: flash[:saved].present?)

confirmation_dialog("Delete project?", message: "This cannot be undone") do
  form(action: project_path(@project), method: :post) do
    # Include the Rails method/CSRF fields required by the application.
    button("Delete", type: "submit")
  end
end
```

`dismiss_path:` makes dismissal route-backed. Without it, a native `form[method=dialog]` closes the browser presentation locally. Mutations remain ordinary authorized Rails forms or links; the DSL does not serialize Ruby callbacks into the browser.

`fallback:` and `dismiss_path:` must be same-origin absolute paths such as `/projects/1/edit`. This makes a missing or unavailable client-side dialog target fall through to an unambiguous Rails route and prevents presentation controls from becoming outbound redirects. A trigger without `fallback:` uses a local fragment and is a JavaScript enhancement; provide a route that renders `presented: true` when the trigger must open the same presentation with JavaScript disabled. A dialog already rendered with `presented: true` remains usable without JavaScript.

Item-driven presentation is supported by passing `item:` instead of `presented:`. A `nil` item emits no dialog, and a non-nil item is yielded to the content block. Clearing or replacing that item remains application/server state.

```ruby
sheet("Edit member", item: @selected_member) do |member|
  member_editor(member)
end
```

## Popover

Popover uses `details`/`summary`, so it is keyboard-operable without JavaScript. Enhancement adds outside-click and Escape dismissal.

```ruby
popover("Quick actions", id: "quick-actions") do
  navigation_link("Archive", destination: archive_project_path(@project))
end
```

## Toolbar

Toolbar renders a labelled `role=toolbar` region. All actions are emitted in the main toolbar and remain normally tabbable in the server HTML. The framework's semantic toolbar command adds roving focus, orientation-aware arrow keys, responsive overflow, and optional minimize-on-scroll behavior.

```ruby
toolbar(
  label: "Editor tools",
  overflow_label: "More editor actions",
  minimize_on_scroll: true,
  minimize_threshold: 24
) do
  toolbar_item(placement: :primary_action, priority: :pinned) { button("Save") }
  toolbar_item(placement: :status, visibility: :visible) { text("Draft") }
  toolbar_item(placement: :secondary_action, priority: :high) { button("Preview") }
  toolbar_item(placement: :secondary_action, priority: :low) { button("Export") }
  toolbar_item(placement: :secondary_action, visibility: :overflow) { button("Advanced") }
end
```

The web contract is explicit:

- `priority:` accepts `:low`, `:automatic`, `:high`, and `:pinned`. When space contracts, low-priority items move first, then automatic items, then high-priority items. Later declarations move before earlier declarations at the same priority so leading actions remain stable.
- `visibility:` accepts `:automatic`, `:visible`, and `:overflow`. Visible items never move. Overflow items enter the disclosure as soon as enhancement connects. A pinned item cannot also require overflow.
- `overflow: false` disables adaptive overflow. It cannot be combined with `minimize_on_scroll: true`.
- `minimize_on_scroll: true` moves every eligible item into overflow after downward scrolling exceeds `minimize_threshold:` pixels. Pinned and visible items remain in the toolbar; scrolling upward or back near the top restores the responsive layout. The nearest scrolling ancestor is used, falling back to the window.

Overflow is a native `details`/`summary` disclosure containing a labelled action group, not an ARIA menu with incorrect `menuitem` roles. Its summary joins the toolbar arrow-key sequence, and overflow actions are reachable with arrow keys whenever the disclosure is open.

The framework runtime moves the original item elements; it never clones buttons, links, forms, identifiers, or input state. Before it connects, the empty disclosure is hidden and every item remains visible and focusable in declaration order. If pinned and visible content alone is wider than the available inline size, those items stay pinned and the main row becomes horizontally scrollable instead of silently dropping actions. Vertical toolbars use the same priority rules when their block size is constrained.

These attributes are stable styling and test hooks:

- `data-swift-ui-presentation-minimized` reports scroll-minimized state.
- `data-swift-ui-presentation-overflow-constrained` reports that immovable items still exceed the available size.
- `data-swift-ui-toolbar-placement`, `data-swift-ui-toolbar-priority`, and `data-swift-ui-toolbar-visibility` expose each declaration.

Placement is a semantic/styling hook; it does not claim Apple toolbar placement or window-management behavior. The responsive algorithm is intentionally a browser equivalent based on measured container space and semantic HTML.
