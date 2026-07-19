# Demo Conventions

How to add a new interactive demo to the test application. After the shared
infrastructure (Phase 0), a stateless demo touches ~5 files and a stateful one
~8, all in predictable locations.

## The one rule that shapes everything

**Each demo owns exactly one Ruby/RenderIR interaction model** and demonstrates
it as *the* Rails-first answer to its problem. Pick the model first; everything
else follows from it. Transport may differ, but no demo may add an
application-authored JavaScript controller, state store, target, event router,
or DOM mutation.

| Situation | Model | Mechanism |
|---|---|---|
| State names a view of data: filters, sort, pagination, selected tab/item, open modal | `:url` | Plain GET links and form submissions; Turbo morphing smooths updates. Zero custom JS. |
| Server-owned domain state mutated by verbs: reorder, add-to-cart, advance | `:turbo` | `Demos::<Name>Controller` + session-backed `Demos::<Name>State` PORO + Turbo Stream `replace` of the demo's root frame. |
| Data changes without user action: telemetry, incoming messages | `:cable` | Action Cable broadcast rendering Turbo Streams into the page (see `showcase/operations`). |
| Declared component interaction: state, bindings, focus, palette filtering, drag preview, keyboard navigation | `:reactive` | Ruby declarations compile to RenderIR; the gem-owned runtime interprets only allowlisted commands and keyed patches. |

For storybook stories demonstrating a *component's* server state with a few
verbs, use `StorySession` + `POST /storybook/component_action`: implement
`handle_<verb>` on the component and add the verb to
`StorybookController::ALLOWED_COMPONENT_ACTIONS` (one line — dispatch is
generic).

## Adding a demo page

1. **Catalog** — add an entry to `app/services/demo_catalog.rb` (slug, name,
   category, description, `model:`, `route:`, accent gradient, optional
   `story:` and `source_component:`). `test/unit/demo_catalog_test.rb` guards
   that everything resolves.
2. **Routes** — a `namespace :demos` block with explicit verbs and regex
   constraints on enum-ish params (see the mission-control routes for the
   pattern).
3. **State** — `app/services/demos/<name>_state.rb`, a session-backed PORO
   modeled on `Showcase::MissionControlState`. All transitions raise
   `ArgumentError` on invalid input. Unit-test it exhaustively in
   `test/services/demos/<name>_state_test.rb`.
4. **Component** — `app/components/demos/<name>_component.rb` using pure
   `swift_ui` DSL. Register it in `config/initializers/swift_ui_rails.rb`
   (`config.allowed_components`) only if it uses reactive restoration.
5. **Controller** — `app/controllers/demos/<name>_controller.rb` inheriting
   `Demos::BaseController`; use `respond_with_demo`/`respond_with_demo_error`
   and override `persist_demo_state`.
6. **View** — thin `app/views/demos/<name>/show.html.erb` rendering the
   component inside `render layout: "demos/shared/demo_chrome"`.
7. **Tests** — the matrix below.

## Adding a storybook story

1. Create `test/components/stories/<name>_stories.rb`; include the same five
   modules as `dsl_button_stories.rb` (TagHelper, TextHelper,
   `ActionView::Context`, `SwiftUIRails::DSL`, `SwiftUIRails::Helpers`).
2. Declare `control :x, as: :select/:number/:boolean/:text/:color, default:`
   for every live control; variant methods accept matching keyword arguments
   with the same defaults. Always define a `:default` variant.
3. Add a `StoryCatalog` entry (`app/services/story_catalog.rb`). Source
   display defaults to on; set `source_display: false` if the story's source
   is not instructive.
4. Run `bin/rails test test/unit/dsl_method_coverage_test.rb
   test/unit/story_catalog_test.rb`. Every chained modifier used in a story
   must exist on the DSL — if it doesn't, add it to the gem (preferred) or
   rethink the chain. Do not widen `NON_DSL_CHAIN_METHODS` casually.

## Test matrix

| Demo type | Required tests |
|---|---|
| Static story | dsl_method_coverage (automatic) + one `update_preview` Turbo Stream controller test |
| Interactive story | + controller test posting non-default control params + one focused system test with `assert_no_console_errors` |
| Stateful story | + component test asserting `handle_*` behavior + one controller test per verb + one rejection test |
| Demo page | state-service unit test (exhaustive) + component render test + controller test (every verb, Turbo Stream format, constraint rejections) + **exactly one** system test driving the headline interaction |

System-suite speed: one system file per demo; push state coverage down to
service/controller tests. The gallery smoke test
(`test/system/demos_index_test.rb`) visits every catalog entry with
`assert_demo_healthy`, so per-demo "does it load" tests are redundant.

## Shared semantic behavior APIs

Reuse or extend a semantic API before introducing behavior. Each declaration
must have a documented RenderIR shape, allowlisted runtime command, and
progressive-enhancement contract:

| DSL intent | Behavior |
|---|---|
| `toast` | Auto-dismissing flash/stream messages and declared hover-pause |
| `reorderable_collection` | Drag and visible move controls submit the same authoritative Rails mutation |
| `on_key_press` | Declarative key to visible-control accelerators |
| `command_palette` | Cmd/Ctrl+K filtering over server-rendered links |
| presentation/lightbox builders | Native `<dialog>` image viewing with declared arrow-key traversal |
| chart interaction commands | Bounded selection and tooltip state over server-rendered SVG |

Rules: no application JavaScript files, Stimulus controllers, controller-style
data attributes, arbitrary command names, DOM queries, or monkey patching. New
behavior must enter the LanguageCatalog and RenderIR vocabulary with validation,
accessibility, security, fallback, and browser-contract tests. Anything that
mutates server state must retain a route-backed semantic fallback.
