# SwiftUI Rails

SwiftUI-inspired, server-rendered views for Rails. SwiftUI Rails combines Ruby blocks, ViewComponent, semantic HTML, Tailwind utilities, and a gem-owned DOM runtime without pretending that a browser is an Apple runtime.

[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7.0-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%206.1.0-red)](https://rubyonrails.org)
[![ViewComponent](https://img.shields.io/badge/view__component-~%3E%203.0-blue)](https://viewcomponent.org)

## What it provides

- Declarative `vstack`, `hstack`, `zstack`, grid, text, image, link, form, and semantic-control builders
- Ruby-native conditional, repeated, and extracted composition
- Semantic typography and color roles, with chainable Tailwind utilities available as an escape hatch
- Chainable HTML, accessibility, Turbo, interaction, and animation metadata modifiers
- Typed props, server-owned `state`, browser-editable `binding`, and authoritative observed resources
- Encrypted, expiring component snapshots and allowlisted server actions
- Bounded keyed RenderIR patches that preserve unchanged DOM nodes and fall back to complete HTML
- Route-first navigation, tabs, dialogs, popovers, toolbars, environment, focus, lifecycle tasks, and gestures
- Accessible charts, bounded canvas commands, schematic maps, sanitized rich text, sandboxed web content, and async images
- Portable web equivalents for WWDC26 reordering, swipe actions, toolbar overflow, and document workflows
- An Xcode-inspired live playground for editing a safe DSL subset and JSON fixtures with responsive previews and diagnostics
- A versioned semantic-language catalogue, source-oriented authoring IR, gem-owned resolved RenderIR, deterministic validation and repair diagnostics, canonical artifacts, and a provider-neutral assistant contract
- Progressive enhancement: native links, forms, disclosure controls, content, and accessible alternatives remain useful when JavaScript is unavailable
- One application model: state, actions, navigation, focus, gestures, and presentation are declared in Ruby and represented in RenderIR; applications do not write JavaScript controllers, targets, selectors, or DOM mutations

## Installation

Add the gem and run the installer:

```ruby
# Gemfile
gem "swift_ui_rails"
```

```bash
bundle install
bin/rails generate swift_ui_rails:install
```

The installer creates `ApplicationComponent`, an example component, the initializer, reactive Rails endpoints, the packaged framework DOM runtime, and styles. When a compatible `view_component-storybook` provider is installed, it also creates the optional Storybook route, configuration, and example; the core runtime does not require Storybook. Review `config/initializers/swift_ui_rails.rb`, then explicitly allow every component that may receive reactive browser requests:

```ruby
SwiftUIRails.configure do |config|
  config.allowed_components << "QuantityComponent"

  # Add tenant/account scope to the built-in Rails session/current-user scope.
  config.reactive_authorization_context = lambda do |_subject|
    Current.account&.id&.to_s
  end
end
```

Generate additional files with:

```bash
bin/rails generate swift_ui_rails:component Quantity
bin/rails generate swift_ui_rails:stories Quantity
```

## A component

```ruby
# app/components/product_row_component.rb
class ProductRowComponent < ApplicationComponent
  prop :product, type: Hash, required: true

  swift_ui do
    component = @component

    hstack(spacing: 12, alignment: :center) do
      vstack(spacing: 4, alignment: :start) do
        text(component.product.fetch(:name))
          .text_style(:headline)

        text(component.product.fetch(:price))
          .text_style(:metadata)
      end

      spacer

      if component.product[:in_stock]
        badge("In Stock", tone: :success, announce: true)
      else
        badge("Back order", tone: :warning, announce: true)
      end
    end
      .p(4)
      .background_style(:surface)
      .rounded("xl")
  end
end
```

Render it like any ViewComponent:

```erb
<%= render ProductRowComponent.new(product: @product) %>
```

## Semantic styling

Application components can describe the purpose of text and color without repeating Tailwind palette values:

```ruby
vstack(alignment: :leading, spacing: 6) do
  text("Deployment status").visually_hidden
  text("Deployment ready").font(:headline).foreground_style(:primary)
  text("Checked 2 minutes ago").text_style(:metadata)
  text("All systems operational").text_style(:supporting).foreground_style(:success)
end
  .padding(4)
  .background_style(:surface)
  .appearance(:deployment_card)
```

`font` selects a SwiftUI-style text role. `foreground_style` and `background_style` select finite semantic color roles, while `text_style` applies a curated font-and-foreground preset. Explicit calls are deterministic: the last call in a category wins. A later `font` or `foreground_style` overrides that facet of a preset, and a later `text_style` resets both facets. Semantic and literal colors share their modifier slots, so a later `text_color` replaces `foreground_style` and a later `bg` replaces `background_style`; reversing either chain makes the semantic role win.

The portable font roles are `large_title`, `title`, `title2`, `title3`, `headline`, `subheadline`, `body`, `callout`, `footnote`, `caption`, and `caption2`. Foreground roles are `primary`, `secondary`, `tertiary`, `quaternary`, `accent`, `success`, `warning`, `danger`, and `on_accent`; background roles are `canvas`, `surface`, `elevated`, `muted`, `accent`, `success`, `warning`, and `danger`. Composite text styles are `title`, `headline`, `body`, `supporting`, `metadata`, and `caption`.

The renderer owns their stable classes and `--swift-ui-*` design tokens, so themes can change centrally rather than by editing every component. Tokens follow the browser's light or dark preference by default; set `data-swift-ui-theme="light"` or `data-swift-ui-theme="dark"` on a container to make that subtree explicit. Applications can override the custom properties without changing component code.

For an application-specific visual that does not belong in the portable role catalog, `.appearance(:deployment_card)` emits the single validated hook `data-swift-ui-appearance="deployment-card"`. Component code names the intent and application CSS owns its browser implementation; appearance names cannot contain utility lists, selectors, or arbitrary CSS. This is the web equivalent of extracting a custom `ViewModifier`, without claiming Swift's generic modifier or environment-driven style semantics. `.visually_hidden` applies the framework-owned accessible hiding treatment, keeping its content available to assistive technology; pass `false` to remove that treatment.

Low-level `.text_color("slate-600")`, `.bg("white")`, `.text_size(...)`, and `.tw(...)` remain available when a design calls for a literal palette value or one-off utility. Prefer semantic roles for product meaning and use those methods as deliberate escape hatches.

## Live playground

The test application includes a developer workspace at `/showcase/playground`. It places a Ruby-like SwiftUI Rails editor, a JSON fixture editor, a sandboxed live canvas, structured line diagnostics, preview-device controls, render metrics, a data inspector, and an authoring/resolved IR inspector in one Xcode-inspired surface. The IDE dogfoods the framework end to end: `SwiftUiRailsPlaygroundComponent` authors the workspace and `ShowcaseApplicationShellComponent` authors the shared navigation and page body with the public SwiftUI Rails DSL. The route ERB only mounts the workspace component; `application.html.erb` is limited to the document/head bootstrap and one shared-shell component mount.

The workspace uses semantic roles plus validated `appearance` hooks instead of presentation classes or `.tw` calls. Its behavior is declared by the Ruby component and lowered through RenderIR. The gem-owned DOM runtime only transports declared events and applies allowlisted commands and keyed patches; it contains no workspace or product logic.

Playground source is deliberately not arbitrary Ruby. The server parses it with Prism, compiles only allowlisted views, expressions, conditionals, and `for_each` blocks into immutable authoring IR, resolves that against bounded fixture data into the same gem-owned RenderIR used by trusted components, and renders it through the IR-native HTML backend. It never sends submitted source to `eval`, `instance_eval`, ERB, constant lookup, helpers, the filesystem, or a generated Ruby file. Invalid edits leave the last successful canvas in place.

The accepted language is published by one versioned, machine-readable catalogue. Compilation, semantic validation, rendering, and canonical formatting are separate phases; structured diagnostics include stable codes, paths, hints, and bounded fixes. Successful runs return canonical DSL plus a verifiable artifact, so source and fixtures—not prompts, assistant settings, or generated HTML—remain the durable work product; assistant-contract changes alone do not invalidate compatible artifacts. An optional server-side model adapter can run the same generate → validate → repair loop without changing the trust boundary. The built-in reliability route measures checked-in candidate and golden-repair conformance, not provider/model performance, and accepts context savings only when executable constraints remain covered. See [Semantic language architecture](docs/semantic_language_architecture.md) for the catalogue/API contract, provider-neutral configuration, artifacts, and reliability metrics. The separate [React versus SwiftUI Rails token benchmark](docs/token_efficiency_benchmark.md) defines the exact static-source comparison, its parity boundary, and the provider experiment required before claiming real LLM output-token savings.

```ruby
vstack(alignment: :leading, spacing: 12) do
  text(data[:title]).text_style(:title)

  for_each(data[:products], id: "id") do |product|
    hstack(spacing: 8) do
      text(product[:name])
      spacer

      if product[:in_stock]
        badge("In Stock", tone: :success)
      else
        badge("Sold Out", tone: :danger)
      end
    end
  end
end
```

Normal application components remain ordinary trusted Ruby and can use `each`, extracted methods, components, and Rails helpers. The narrower playground grammar exists only at the browser-submitted code boundary. See [Live playground](docs/playground.md) for its exact syntax, limits, and threat model.

Ruby `if`, `case`, `each`, helper methods, and small extracted components are the composition model. Repeated styling such as the stock pill belongs in a named view like `badge`, keeping call sites shorter than a long modifier chain.

## Layout and modifiers

```ruby
swift_ui do
  vstack(spacing: 16, alignment: :start) do
    text("Account").text_style(:title)

    grid(columns: 3, spacing: 12) do
      accounts.each { |account| render AccountCardComponent.new(account:) }
    end

    button("Continue")
      .button_style(:primary)
      .accessibility_hint("Opens the billing step")
      .tw("w-full sm:w-auto")
  end
end
```

Named modifiers cover common Tailwind utilities and web semantics; `.tw(...)` composes application-owned utility classes. Modifiers return the element, so they can be split over lines or extracted into reusable components. See [accessibility and animation](docs/accessibility_and_animation.md) for the exact browser contract.

Insertion and removal animations mirror `View.transition` with SwiftUI's `asymmetric(insertion:removal:)` value: `.transition(insertion: :move_up, removal: :opacity)` plays a CSS entrance when the element enters the DOM (including Turbo Stream inserts) and declares the exit a small `turbo:before-stream-render` hook plays before removal. Names (`:opacity`, `:move_up`, `:move_down`, `:scale`, `:blur`) are allowlisted and unknown values raise. Called without keywords, `.transition` remains the plain Tailwind utility. Value-driven animation stays `.animation(value:)`, and pressed feedback belongs in button styles (`button_style(:springy)`).

## State, Binding, and Observation

Component interaction state is owned by Rails. The browser transports declared binding edits and action capabilities; it does not become a second application state store.

```ruby
class QuantityComponent < ApplicationComponent
  prop :label, type: String, default: "Quantity"
  state :count, 0, type: Integer
  binding :step, type: Integer, default: 1

  observed_resource :inventory, stream: :inventory do
    { available: Inventory.available_count }
  end

  swift_ui do
    component = @component

    vstack(spacing: 12, alignment: :start) do
      text("#{component.label}: #{component.count}")
        .content_transition(:numeric_text)
        .animation(value: component.count)

      label("Step", for_input: "quantity-step")
      input(
        id: "quantity-step",
        type: "number",
        min: 1,
        **component.step.input_attributes
      )

      text("Available: #{component.inventory.data.fetch(:available)}")

      button("Increase").on_click do
        component.count += component.step.value
      end
    end
  end
end
```

- `state` is local, server-owned component state. Supplying `type:` validates defaults, assignments, and restored snapshots.
- `binding` is an explicit two-way value. Its `input_attributes`, `checkbox_attributes`, and `select_attributes` produce normal form fallbacks plus typed reactive metadata.
- `observed_resource` reloads authoritative data from a database, cache, or service. After a committed mutation, call `SwiftUIRails::Reactive::ObservableStore.invalidate(:inventory)` to broadcast an opaque invalidation—not the resource value.

An action such as `.on_click` is registered during render. A request must return the encrypted snapshot and short-lived stream capability issued for that component ID, class, action descriptor, and authorization context. The server restores only declared values and executes the allowlisted action. The gem-owned DOM runtime negotiates a bounded keyed RenderIR patch, preserving unchanged DOM objects and focused controls; old clients, cache misses, unsafe or oversized trees, and patches no smaller than the canonical response receive complete replacement HTML. Props are constructor input, not browser-writable state. See [Semantic language architecture](docs/semantic_language_architecture.md) for the protocol boundary and measured patch-planning gate.

Read the full [state, binding, and observation contract](docs/state_binding_observation.md) before exposing reactive components.

## Navigation, presentation, and interaction

Navigation stays route-first: Rails routes, Turbo visits, browser history, and normal anchors remain authoritative.

```ruby
navigation_stack(label: "Project") do
  navigation_link("Overview", destination: project_path(project), current: true)

  tab_view(id: "project-tabs", label: "Project sections", selection: :activity) do
    tab("Overview", value: :overview) { project_overview }
    tab("Activity", value: :activity) { project_activity }
  end

  presentation_trigger("Edit", target: "edit-project", fallback: edit_project_path(project))
  sheet("Edit project", id: "edit-project", presented: params[:edit].present?) do
    render ProjectFormComponent.new(project:)
  end
end
```

The same family includes `alert`, `confirmation_dialog`, item-driven sheets, `popover`, and adaptive `toolbar`/`toolbar_item`. Native `dialog`, `details`, links, and route fallbacks provide the base behavior; semantic RenderIR commands let the framework runtime add modal focus, local-tab history, keyboard roving, dismissal, and responsive toolbar overflow. See [navigation and presentation](docs/navigation_and_presentation.md).

Environment, focus, lifecycle, and interaction APIs preserve portable intent while respecting browser ownership:

```ruby
class SearchComponent < ApplicationComponent
  environment :locale, default: "en", type: String
  focus_state :focused_field, values: %i[query]

  swift_ui do
    component = @component

    lifecycle_scope(id: "search") do
      textfield(name: "query", placeholder: "Search")
        .focused(:focused_field, equals: :query)
        .on_key_press(keys: :k, modifiers: %i[control]) do
          component.focused_field = :query
        end
    end
      .on_appear
      .task(url: "/search/suggestions", method: :get)
  end
end
```

Use `with_environment`/`environment_scope` for fiber-local server values, `.focusable` and `.default_focus` for focus intent, and `.on_tap`, `.on_long_press`, `.on_drag`, `.on_hover`, and `.on_key_press` for bounded enhancements. Critical persistence must remain an explicit Rails mutation; browser disconnect and disappear events are best effort. See [environment and interaction](docs/environment_interaction.md).

## Advanced content

The rich-content APIs expose deliberately narrow web contracts:

```ruby
async_image("/product.png", alt: "Product front view")

rich_text(editorial_html)

chart(
  { "Mon" => 18, "Tue" => 31, "Wed" => 27 },
  type: :line,
  title: "Successful deployments",
  description: "Deployments this week"
)

canvas(
  label: "Service health drawing",
  width: 640,
  height: 360,
  commands: [{ type: :fill_rect, x: 20, y: 20, width: 80, height: 40, color: :green }]
)

map(
  center: [51.5074, -0.1278],
  span: [0.18, 0.32],
  label: "London service points",
  markers: [map_marker(latitude: 51.5074, longitude: -0.1278, label: "Westminster")]
)

web_view("/reports/preview", title: "Report preview")
```

`rich_text` sanitizes to a fixed semantic allowlist. `chart` renders described SVG plus exact tabular values. `canvas` accepts a bounded command vocabulary without eval or arbitrary paths. `map` is a privacy-preserving schematic, not MapKit or turn-by-turn navigation. `web_view` is a sandboxed iframe for a validated same-origin or explicitly allowlisted host. Details and security constraints are in [advanced content](docs/advanced_content.md).

`icon(name, size: 16)` renders a decorative glyph from a curated allowlist of ~30 names (`check`, `plus`, `chevron_right`, `arrow_up`, `warning`, `gear`, `menu`, `sun`, `moon`, `play`, `refresh`, `mail`, `trash`, `clock`, `bolt`, …). Unknown names raise, sizes are clamped to 1–256 px, and the glyph is `aria-hidden` by default. For custom artwork use `image()` with an SVG asset rather than extending the glyph table.

## Portable WWDC26 workflows

SwiftUI Rails implements web equivalents where the underlying product intent is portable:

```ruby
reorderable_collection(
  items: @projects,
  key: :id,
  item_label: :name,
  move_path: projects_order_path,
  label: "Project order"
) { |project, _index| project_card(project) }

archive = swipe_action("Archive", action: archive_message_path(message), method: :patch)
swipe_actions(label: message.subject, actions: [archive]) { message_row(message) }

document_workflow(label: "Project documents") do
  document_import(
    action: project_documents_path(project),
    accept: [".pdf", "application/pdf"],
    max_bytes: 10.megabytes,
    label: "Project brief",
    submit_label: "Import"
  )

  document_export(
    "Export CSV",
    destination: export_project_path(project, format: :csv),
    filename: "project.csv",
    content_type: "text/csv"
  )
end
```

Move controls, visible swipe-action forms, multipart upload, and download anchors work without JavaScript. Enhancement adds drag submission, pointer-swipe disclosure, progress feedback, and adaptive toolbar behavior while Rails remains the mutation and authorization boundary. Upload hints are not validation; controllers must recheck size, content type, provenance, ownership, and file safety. See [portable workflows](docs/portable_workflows.md).

## Security model

SwiftUI Rails narrows rendering and reactive inputs, but it does not replace normal Rails security:

- Reactive components are deny-by-default through `config.allowed_components`.
- Encrypted, expiring snapshots are bound to the component ID/class; short-lived capabilities are bound to the request authorization context.
- Action descriptors, declared bindings, value types, payload size/depth, URLs, HTML, CSS-like values, canvas commands, and workflow metadata are validated or bounded.
- Observed values and raw component state are not emitted as public DOM metadata or Action Cable payloads.
- Forms and mutations still require Rails CSRF protection, authentication, authorization, tenant checks, transaction boundaries, and server-side validation.
- Rich text, iframes, uploads, external hosts, downloads, and task endpoints each have additional documented policies. A signed value proves integrity, not permission.

Prefer scalar IDs in reactive props and load authorized records again on the server. Never put secrets in rendered output, and never treat environment values, client-side file checks, gesture recognition, or Storybook controls as authorization.

## Progressive enhancement

The initial response is semantic server-rendered HTML. Links navigate, forms submit, `details` disclosures open, action alternatives remain focusable, chart values remain readable, and fallback content remains present without the framework runtime. Turbo and Action Cable may transport navigation or invalidation, while the gem-owned runtime applies declared keyed updates, focus, dialogs, gestures, async phases, canvas drawing, and workflow feedback.

Some interactions are necessarily enhancement-only—for example local dialog triggers without a route fallback, canvas pixels, or live focus restoration. Each feature document states the no-JavaScript contract; provide an ordinary Rails route or semantic fallback when the interaction is essential.

## One cognitive model

Application code is Ruby plus the SwiftUI Rails semantic DSL. A component may
declare state, bindings, actions, navigation, presentation, focus, gestures,
tasks, and portable browser commands; those declarations become validated
RenderIR. Do not add Stimulus controllers, `data-controller`, `data-action`,
controller targets, application event routers, `querySelector` calls, or direct
DOM mutation to implement product behavior.

The small JavaScript package shipped by the gem is infrastructure, not a second
application layer. It delegates declared browser events, submits signed action
and binding payloads to Rails, validates responses, applies keyed DOM patches,
and executes a fixed allowlist of browser commands such as focus, present,
dismiss, navigate, and copy. It must never import application modules or know
product concepts. If a behavior cannot be expressed in Ruby and represented in
RenderIR, add a bounded semantic language feature before using it in an
application.

## SwiftUI compatibility boundary

This project follows SwiftUI's declarative vocabulary where it maps honestly to Rails and the web. Its correctness target is a small, expressive, versioned semantic UI language—not one-to-one coverage of every SwiftUI API. It does **not** run Swift, implement Apple's result builders, reproduce `NavigationPath`, emulate SwiftUI's render engine or identity rules, expose UIKit/AppKit/MapKit, manage Apple scenes/windows, adopt OS materials, or provide device-only APIs.

Features are classified as:

- **supported** when the portable intent has a first-class gem API;
- **partial** when the available web semantics are deliberately narrower;
- **web equivalent** when Rails or browser behavior is the correct authority; and
- **not applicable** for Apple compiler, OS, hardware, and native-host capabilities.

Delivery status is tracked separately, so an available partial feature is not advertised as native semantic parity. Read the executable matrix and evidence in [SwiftUI compatibility](docs/swiftui_compatibility.md).

## Component lab

The repository test application includes 16 curated labs, including:

- Atlas Mission Control, a source-visible complete application composition combining navigation, telemetry, orbital visuals, reordering, presentations, alerts, and document workflows;
- navigation, tabs, presentations, and adaptive toolbars;
- async images, rich text, charts, safe canvas, schematic maps, and sandboxed web content; and
- portable WWDC26 reorder, swipe, and document workflows.

Run the test application and open `/showcase/mission-control` for the full Atlas workflow or `/rails/stories/atlas_mission_control?variant=command_center` to inspect the same component with its complete trusted DSL source. The full lab index remains at `/rails/stories`. A generated host application with a compatible optional ViewComponent Storybook provider receives its setup under `/swift_ui/storybook`; without that provider, installation skips only the Storybook files and keeps the core DSL fully usable.

## Testing and development

```bash
bundle install
(cd test_app && bundle install)

# Behavioral suite
bundle exec rake

# Rails, browser, and security slices
bundle exec rake test:rails
bundle exec rake test:system
bundle exec rake security:all

# Run the test application
cd test_app
bin/dev
```

A focused component test remains ordinary ViewComponent testing:

```ruby
class ProductRowComponentTest < ViewComponent::TestCase
  test "renders stock status" do
    render_inline ProductRowComponent.new(
      product: { name: "Field Notes", price: "£12", in_stock: true }
    )

    assert_selector "[role='status']", text: "In Stock"
  end
end
```

## Documentation

- [SwiftUI compatibility matrix](docs/swiftui_compatibility.md)
- [State, binding, and observation](docs/state_binding_observation.md)
- [Navigation and presentation](docs/navigation_and_presentation.md)
- [Environment, focus, lifecycle, and interactions](docs/environment_interaction.md)
- [Advanced content](docs/advanced_content.md)
- [Portable WWDC26 workflows](docs/portable_workflows.md)
- [Live playground](docs/playground.md)
- [Semantic language architecture](docs/semantic_language_architecture.md)
- [DSL authoring guide](docs/dsl_authoring.md)
- [Accessibility and animation](docs/accessibility_and_animation.md)
- [Grid properties](docs/grid_properties.md)
- [Authentication forms](docs/auth_forms_dsl.md)

## License

SwiftUI Rails is available under the [MIT License](https://opensource.org/licenses/MIT).
