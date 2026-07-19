# Portable WWDC26 workflows

SwiftUI Rails represents portable collection and document concepts using Rails routes and native HTML. These APIs are web equivalents, not claims that a browser has SwiftUI's in-process state, gesture recognizers, or document scene lifecycle.

## Reordering arbitrary collections

`reorderable_collection` works with list, grid, and custom CSS layouts. Identity comes from the supplied stable key, never the current array index.

```ruby
reorderable_collection(
  items: @stages,
  key: :slug,
  item_label: :name,
  move_path: project_stage_order_path(@project),
  label: "Delivery stages",
  layout: :grid,
  columns: 2,
  method: :patch
) do |stage, index|
  text("#{index + 1}. #{stage.name}")
end
```

Every item renders visible `Move up` and `Move down` submit buttons. They are the universal keyboard, switch-control, voice-control, pointer, and no-JavaScript path. Optional HTML drag and drop submits the same route with stable keys; the client never permanently rearranges the DOM.

The endpoint receives one of two contracts:

```ruby
# Keyboard controls
params.expect(reorder: %i[item_key direction])
# => { item_key: "design", direction: "up" }

# Drag enhancement
params.expect(reorder: %i[item_key target_key placement])
# => { item_key: "design", target_key: "release", placement: "before" }
```

The controller must authorize the collection, confirm every key belongs to it, reject duplicate or stale keys, persist the new position transactionally, and render or redirect to the authoritative order. The DSL bounds a rendered collection to 500 items and stable keys to 256 bytes.

Use `layout: :list`, `:grid`, or `:custom`. `:custom` adds no layout CSS, so application styles can implement any arrangement while retaining the item wrappers and controls.

## Swipe actions

Build validated actions with `swipe_action`, then pass them to `swipe_actions`:

```ruby
archive = swipe_action(
  "Archive",
  action: archive_message_path(message),
  method: :patch,
  tone: :accent
)
destroy = swipe_action(
  "Delete",
  action: message_path(message),
  method: :delete,
  tone: :destructive
)

swipe_actions(label: message.subject, actions: [archive, destroy]) do
  text(message.subject)
end
```

The action rail is always visible and its real Rails form buttons remain in normal focus order. A leading or trailing pointer swipe only marks the row as revealed and announces that actions are available. It never submits, deletes, archives, or treats a gesture as authorization. Full-swipe execution is intentionally absent.

Mutation destinations must be same-origin absolute paths. Methods are limited to `POST`, `PATCH`, `PUT`, and `DELETE`; GET navigation belongs in a normal link. Forms include Rails authenticity tokens in request-backed rendering and opt out of Turbo so a full-page fallback, CSP nonces, redirects, and validation errors behave consistently.

## Document import and creation

`document_import` creates a multipart Rails form with a native file input, signed creation context, bounded client hint, upload status, and native `<progress>` element:

```ruby
document_import(
  action: documents_path,
  accept: [".pdf", "application/pdf"],
  max_bytes: 10.megabytes,
  source: :import,
  metadata: { workspace_id: @workspace.id },
  label: "Project brief",
  submit_label: "Import"
)
```

`accept` and the framework runtime's declared size hint improve feedback but are not security controls. Enforce the same policy on the server before attaching or parsing bytes:

```ruby
upload = params.expect(document: %i[file creation_context]).fetch(:file)
context = SwiftUIRails::DocumentWorkflow.verify_creation_context!(
  params.dig(:document, :creation_context)
)
SwiftUIRails::DocumentWorkflow.validate_upload!(
  upload,
  max_bytes: 10.megabytes,
  content_types: ["application/pdf"]
)

current_user.documents.create!(
  file: upload,
  creation_source: context.fetch(:source),
  creation_metadata: context.fetch(:metadata)
)
```

`validate_upload!` enforces the byte envelope, filename shape, declared MIME allowlist, and a Marcel inspection of the uploaded bytes. Both the declared and detected types must be allowed, and uploads whose content cannot be inspected fail closed. Content identification still does not make untrusted bytes safe to parse: use a format parser with explicit resource limits, quarantine and scan uploads appropriate to the threat model, and never execute an imported document.

Creation sources are restricted to `:new`, `:import`, `:template`, `:duplicate`, and `:generated`. Metadata is a signed, expiring envelope of at most 20 scalar JSON fields and 4 KB. Treat it as provenance, not authorization: the controller still verifies referenced records belong to the current user.

For Active Storage Direct Upload, enable the conventional input attribute:

```ruby
document_import(
  action: documents_path,
  accept: "application/pdf",
  max_bytes: 10.megabytes,
  direct_upload: true
)
```

When Active Storage routes exist, the DSL resolves `rails_direct_uploads_path`; otherwise pass a validated `direct_upload_url`. The gem-owned runtime maps Active Storage's `direct-upload:*` events onto the declared progress state. A normal multipart navigation can only show indeterminate progress because the browser does not expose its uploaded byte count to page JavaScript.

Use `document_creation_action` for a CSRF-protected new/template/duplicate/generated flow without a file:

```ruby
document_creation_action(
  "Create from template",
  action: documents_path,
  source: :template,
  metadata: { template_id: template.id }
)
```

## Streaming export

`document_export` is a same-origin GET anchor with Turbo disabled and an optional filename/type hint:

```ruby
document_export(
  "Export CSV",
  destination: export_project_path(@project, format: :csv),
  filename: "project.csv",
  content_type: "text/csv"
)
```

The Rails action owns authorization and response policy. Use `send_data`, `send_file`, or an enumerator response, set an exact `Content-Type` and `Content-Disposition`, prevent spreadsheet formula injection for tabular formats, and choose cache headers appropriate to the document's sensitivity.

## Framework runtime contract

Move buttons, swipe action forms, multipart import, creation, and export all remain operable before the framework runtime connects. Ruby workflow declarations may opt into bounded drag submission, pointer-swipe announcements, file-size feedback, and Active Storage/Turbo progress mapping. These are allowlisted RenderIR commands handled by the shared gem runtime, not an application JavaScript controller or a second workflow state store.

The runnable story is available at `/rails/stories/wwdc26_workflows?variant=portable_workflows` in the test application.
