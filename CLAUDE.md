# SwiftUI Rails repository instructions

This file is the checked-in instruction contract for coding assistants working
in this repository. The canonical DSL rules live in
[docs/dsl_authoring.md](docs/dsl_authoring.md), and the architecture contract
lives in
[docs/semantic_language_architecture.md](docs/semantic_language_architecture.md).
Where another example disagrees with either document, those documents win.

## Product objective

SwiftUI Rails is a small, expressive, versioned semantic UI language for Rails
and the web. Correctness, accessibility, security, stable identity, and token
efficiency matter more than translating every SwiftUI API or exposing every
browser primitive.

Trusted application components are ordinary Ruby. Browser-submitted Playground
source is a smaller Ruby-shaped language compiled through Prism into inert
authoring IR. Both trusted components and Playground programs resolve into the
same immutable, validated `SwiftUIRails::RenderIR` before HTML rendering.

## The one cognitive model

Ruby plus RenderIR is the complete application programming model.

- Own application state in Rails components, models, services, sessions,
  databases, URLs, or other server-authoritative stores.
- Declare component state and bindings with `state` and `binding`.
- Declare actions, navigation, presentation, focus, gestures, tasks, and
  workflow behavior with SwiftUI Rails semantic APIs.
- Represent application behavior in validated RenderIR.
- Let the gem-owned DOM runtime transport declared events, validate signed
  responses, apply keyed patches, preserve native editing state, and interpret
  a fixed allowlist of semantic browser commands.

Do not create application JavaScript controllers, application event routers,
controller targets, selector-based behavior, inline handlers, or direct DOM
mutation. Do not emit `data-controller`, `data-action`, `data-*-target`, or
`event->controller#method` strings. Do not recreate the same architecture under
a different controller or micro-framework name.

The browser runtime is infrastructure, not an application extension surface.
It must not import application modules, own product state, dispatch arbitrary
method names, or understand product concepts. If a required behavior cannot be
expressed in Ruby and RenderIR, implement it as one bounded framework feature:

1. add semantic vocabulary to the appropriate catalogue/API;
2. define the versioned RenderIR shape;
3. validate arguments, legal composition, identity, security, and
   accessibility;
4. render a progressive semantic HTML fallback;
5. add a finite runtime command only when native HTML cannot provide the
   behavior;
6. add unit, IR, security, accessibility, and browser-contract tests;
7. document and version the new behavior.

## Component pattern

```ruby
class QuantityComponent < ApplicationComponent
  prop :label, type: String, default: "Quantity"
  state :count, 0, type: Integer
  binding :step, type: Integer, default: 1

  swift_ui do
    component = @component

    vstack(alignment: :leading, spacing: 12) do
      text("#{component.label}: #{component.count}")
        .text_style(:headline)

      label("Step", for_input: "quantity-step")
      input(
        id: "quantity-step",
        type: "number",
        min: 1,
        **component.step.input_attributes
      )

      button("Increase")
        .button_style(:primary)
        .on_click { component.count += component.step.value }
    end
  end
end
```

Reactive components are deny-by-default. Add only reviewed component classes to
`config.allowed_components`. Keep reactive props and snapshot state bounded and
JSON-like; carry scalar record IDs, then reload and authorize records on every
server action. A signed capability proves integrity, not authorization.

## Authoring rules

- Prefer semantic views and roles: `badge`, `text_style`, `font`,
  `foreground_style`, `background_style`, `button_style`, and named
  application `appearance` hooks.
- Use validated literal modifiers only when semantic vocabulary cannot express
  the design. Treat `.tw(...)` as a deliberate presentation escape hatch.
- Use Ruby `if`, `case`, iteration, helper methods, and extracted components for
  composition.
- Give repeated RenderIR content stable identity. Playground `for_each` always
  requires a unique stable `id` key.
- Use native links, forms, buttons, details, dialogs, progress, and other
  semantic elements so the useful path remains available before the runtime
  connects.
- Keep routes and Rails controllers authoritative for navigation, mutations,
  authentication, authorization, validation, and transaction boundaries.
- Do not serialize callbacks, Active Record instances, secrets, arbitrary
  attributes, raw HTML, executable URLs, or provider credentials into IR.

## Playground and LLM generation

`Showcase::Playground::LanguageCatalog` is the single source of vocabulary for
browser-submitted code, autocomplete, documentation, validation, and model
context. `LanguageCatalog.for_generation` is the default semantic-only model
contract. Do not hand-maintain a second list of supported calls.

Generated Playground responses must contain exactly one DSL root and no
Markdown fence or explanation. Use only catalogued builders, modifiers,
statements, expressions, arguments, and enum values. Read dynamic values only
from fixture data or the active `for_each` value. Never generate arbitrary
Ruby, JavaScript, controller metadata, DOM operations, URLs, raw HTML, or
presentation escape hatches omitted from the compact contract.

The durable artifact is canonical DSL plus fixture data, language/IR versions,
and executable expectations. Prompts are disposable. All generated source goes
through parse, compile, semantic validation, RenderIR validation, bounded
rendering, and repair; it is never evaluated as Ruby.

When assistant instructions or response semantics change, bump
`AssistantContract::CONTRACT_VERSION`. When catalogue constraints or language
semantics change, bump `LanguageCatalog::VERSION` and update tests and durable
fixtures. Do not make an unversioned contract change.

## Progressive enhancement boundary

The initial response is semantic server-rendered HTML. The framework runtime may
add keyed selective updates, focus restoration, presentation, bounded gestures,
task phases, drag previews, progress reporting, and other declared commands.
Essential interactions need an ordinary Rails route, link, form, or semantic
fallback. Browser lifecycle/disconnect events are best effort and must not own
critical persistence.

Turbo and Action Cable are transports, not alternative application state
models. They may navigate, submit, stream HTML, or signal authoritative server
invalidation. They do not authorize client-owned domain state.

## Security requirements

- Preserve Rails CSRF protection, authentication, authorization, tenant
  isolation, validation, and request limits.
- Keep reactive restoration deny-by-default and bind capabilities to component
  identity, authorization context, expiry, and one-time snapshots.
- Validate URLs, attributes, CSS-like values, rich text, iframe policies,
  uploads, canvas commands, action names, bindings, and protocol payloads.
- Reject scripts, inline event handlers, unsafe schemes, unsandboxed active
  content, arbitrary browser commands, and controller-style metadata.
- Treat browser file checks, gesture recognition, environment values, and
  Storybook controls as user experience hints, never authorization.
- Prefer fail-closed behavior with domain diagnostics and bounded repair hints.

## Development commands

```bash
bundle install
(cd test_app && bundle install)

# Full default gate
bundle exec rake

# Focused Rails, browser, and security gates
bundle exec rake test:rails
bundle exec rake test:system
bundle exec rake security:all

# Lint one or all trusted components through RenderIR
bin/rails swift_ui:lint FILE=app/components/example_component.rb
bin/rails swift_ui:lint FORMAT=json

# Compile browser-submitted DSL through the restricted pipeline
echo 'vstack { text("Hello") }' | bin/rails playground:compile

# Run the test application
cd test_app
bin/dev
```

Useful focused checks:

```bash
cd test_app
bin/rails test test/services/showcase/playground_language_catalog_test.rb
bin/rails test test/services/showcase/playground_assistant_contract_test.rb
bin/rails test test/unit/dsl_method_coverage_test.rb
bin/rails test:system
```

Use `rg` for source searches. Preserve unrelated changes in the working tree.
Use `apply_patch` for intentional file edits. Run the narrowest relevant tests
first, then the proportional full gate. Do not weaken a failing security,
catalogue, IR, sample-source, or browser-contract test merely to retain a legacy
application-JavaScript pattern.

## Storybook and demos

Stories under `test_app/test/components/stories` are checked-in executable
documentation. They must use the public Ruby DSL and must not teach or emit
application browser-controller hooks. `DslMethodCoverageTest` enforces both DSL
method coverage and this one-model boundary.

Every interactive demo declares one Rails/RenderIR authority model in
`DemoCatalog`. URL requests, reactive keyed actions, Turbo Streams, and Action
Cable are transport choices. Demo components must remain pure Ruby DSL, and
their no-runtime route or semantic fallback must stay usable for essential
behavior.

The Playground at `/showcase/playground` dogfoods the same rule: its visible UI
is authored in SwiftUI Rails, its editor behavior is declared in Ruby/RenderIR,
and its browser package is the shared framework protocol interpreter rather
than a product-specific controller.
