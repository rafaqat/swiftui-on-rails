# Live playground

The showcase application exposes an Xcode-inspired workspace at `/showcase/playground`. It is a developer tool for trying SwiftUI Rails composition against editable JSON fixtures without creating or loading a Ruby file. The workspace dogfoods the framework end to end: `SwiftUiRailsPlaygroundComponent` builds the toolbar, navigator, editors, canvas, debug panels, and status bar, while `ShowcaseApplicationShellComponent` builds the shared navigation and page body with the public SwiftUI Rails DSL. The route ERB contains only the workspace component mount. The application layout retains the document/head bootstrap and mounts the shared shell component; it does not hand-author visible body chrome.

The trusted workspace components use semantic roles, framework modifiers, and validated `appearance` identifiers rather than presentation classes or `.tw` calls. Workspace state and behavior are declared in Ruby and represented in RenderIR. The gem-owned DOM runtime only interprets allowlisted editor commands and records live state through ARIA, fixed framework data, and native element properties; there is no application-authored JavaScript controller. This application-side `appearance` API does not widen the browser-submitted playground grammar described below.

The workspace provides:

- a curated example navigator;
- `View.rb` and `Data.json` editors with line numbers, tab insertion, revision-aware draft restoration, auto-run, and Command/Control+Enter;
- desktop, tablet, and phone canvas sizes with zoom and background controls;
- a script-disabled, sandboxed preview frame;
- located compiler and fixture diagnostics;
- render timing, node, view, loop, operation, and output-size metrics;
- a data inspector and a bounded local preview-event console;
- an IR inspector showing both source-oriented authoring IR and resolved gem
  RenderIR, including schemas, versions, node counts, and canonical JSON.

## Security boundary

Browser-submitted source is untrusted input. It never enters Ruby evaluation, ERB, a generated class, a normal component block, or a dynamic helper call.

```text
View.rb -> Prism parser -> strict AST compiler -> authoring IR
                                             -> semantic validator
Data.json -> strict JSON parser -> frozen primitive tree
validated authoring IR + data -> bounded evaluator -> resolved RenderIR
resolved RenderIR -> domain validator -> IR-native renderer -> escaped HTML
```

The compiler rejects a program if Prism reports any syntax error. Every supported syntax node has an explicit compiler branch; every other node becomes a diagnostic. The semantic validator independently checks IR and language versions, node shapes, block and parent rules, modifier targets, argument types, scope, and collection identity before rendering. The renderer uses fixed `case` branches for views and modifiers—there is no user-controlled `send`, `public_send`, constantization, component name, attribute map, URL, raw HTML, JavaScript, Stimulus controller, DOM selector, or event-handler attribute.

`for_each` identity is not validation-only metadata. Each direct item root gets
a deterministic digest-backed RenderIR/DOM morph identity. Keys survive fixture
reordering, multiple roots receive declaration-order ordinals, nested loops
include parent ancestry, and string/integer keys remain distinct.

The normal `DSLContext` still uses trusted Ruby closures to collect nested
elements. The fixed evaluator creates those closures itself from inert
authoring IR; submitted source is never executable and never becomes a
closure. The resulting elements lower to immutable RenderIR and the HTML
backend does not execute them again. Preview HTML is placed in an iframe with
`sandbox="allow-same-origin"` and no script, form, pop-up, or top-navigation
permissions. Fixture strings flow through Rails escaping.

## Playground grammar

The initial language supports these views:

- `vstack`, `hstack`, `zstack`, and `grid`;
- `section` and `article`;
- `text`, `button`, `badge`, and `icon`;
- `spacer`, `divider`, `progress_view`, and `gauge`.

Composition supports one root view, nested view blocks, `if`/`elsif`/`else`, `unless`, and stable fixture repetition:

```ruby
for_each(data[:products], id: "id") do |product|
  text(product[:name])
end
```

The fixture root must be a JSON object. `data[:key]` and `item[:key]` read string-backed JSON keys without symbolizing user input. Expressions support scalar literals, interpolation, indexing, `==`, `!=`, ordered comparisons, boolean operators, numeric arithmetic, and the fixed read operations `count`, `length`, `size`, `empty?`, `first`, and `last`.

Supported modifiers cover bounded spacing, sizing, colors, typography, borders, corners, shadows, opacity, visibility, disabled state, and fixed button styles/sizes. The semantic styling layer is available through finite role-based modifiers:

- `foreground_style`: `primary`, `secondary`, `tertiary`, `quaternary`, `accent`, `success`, `warning`, `danger`, and `on_accent`;
- `background_style`: `canvas`, `surface`, `elevated`, `muted`, `accent`, `success`, `warning`, and `danger`;
- `font`: `large_title`, `title`, `title2`, `title3`, `headline`, `subheadline`, `body`, `callout`, `footnote`, `caption`, and `caption2`;
- `text_style`: `title`, `headline`, `body`, `supporting`, `metadata`, and `caption`.

For example, `text(product[:description]).text_style(:supporting)` expresses application intent without embedding Tailwind color and size tokens. Fixture data can also select an allowlisted role with `foreground_style(product[:accent_role])`, keeping dynamic examples inside the same theme contract. Low-level `text_color`, `text_size`, and `bg` remain available only as deliberate escape hatches for exact brand or experimental values. Every value is checked against a finite enum or numeric range before the underlying element method is called. Arbitrary `.tw`, inline style, attributes, URLs, event handlers, raw HTML, application JavaScript, Stimulus metadata, and reactive server actions are intentionally unavailable.

Playground buttons are non-submitting visual controls. The untrusted playground profile does not expose action names or emit inert event metadata; interactive application examples use typed component state and signed Rails actions outside this constrained preview language.

## Versioned language and authoring tools

`Showcase::Playground::LanguageCatalog` is the JSON-native contract for this browser language. Compiler call shapes, renderer enums, editor metadata, legal composition, security notes, and the compact LLM contract share its language version. `LanguageCatalog.for_generation` is semantic-only by default, keeping low-level presentation escape hatches out of ordinary generated source.

Every successful run returns canonical source and a versioned artifact containing the DSL, fixture, language metadata, semantic-IR digest, and verification expectations. `SourceFormatter` proves its output recompiles to the same semantic IR; `ArtifactVerifier` recompiles artifacts rather than trusting stored HTML or IR. Prompts, assistant-contract fingerprints, and provider settings are not durable artifacts, so changing assistant instructions does not invalidate otherwise compatible saved DSL.

The optional `AssistantSession` accepts a server-side callable model adapter and performs at most three generate → validate → repair attempts through the same runner used for manual edits. Configure the adapter at `Rails.application.config.x.swift_ui_playground.generator`; it receives `messages:` plus a bounded `response:` contract and returns plain DSL source. No provider SDK is required by the playground, and an unconfigured assistant fails closed without affecting manual compilation.

The showcase exposes JSON tooling routes for development:

| Route | Contract |
| --- | --- |
| `GET /showcase/playground/language` | Full catalogue, compact generation contract, fingerprint, and IR versions |
| `POST /showcase/playground/compile` | `{ source, data_json, revision }` → preview, diagnostics, canonical source, metrics, and artifact |
| `POST /showcase/playground/assist` | `{ instruction, data_json, source? }` → bounded assistant session result |
| `POST /showcase/playground/verify` | `{ artifact }` → fresh contract, fixture, compile, semantic, and runtime verification |
| `GET /showcase/playground/reliability` | Deterministic recorded-candidate, golden-repair, semantic, accessibility, unsafe-rejection, and context-efficiency conformance; no provider/model execution |

The reliability corpus runs checked-in candidate DSL and checked-in golden repairs through the real compiler and renderer. Its prompt text is descriptive metadata: this route does not invoke `AssistantSession` or a model, so model first-pass and repair rates remain unavailable without a separately configured provider evaluation. Context efficiency passes only when the compact contract is smaller and preserves every validity-affecting constraint in its semantic generation profile.

See [Semantic language architecture](semantic_language_architecture.md) for provider-neutral adapter configuration, CSRF-aware HTTP use, direct Ruby usage, artifact semantics, versioning rules, and the exact reliability report fields.

## Rejected Ruby

Assignments, constants, method/class/module definitions, lambdas, arbitrary calls, reflection, dynamic symbols, `while`/`until`, rescue/ensure, globals, instance variables, backticks, regular expressions, and process/file/network APIs are outside the language. Examples such as `eval`, `system`, `File.read`, `send`, `html_safe`, and `tw` produce diagnostics and cannot execute.

## Deterministic limits

The controller and runner enforce limits before and during request handling, compilation, and rendering:

| Resource | Limit |
| --- | ---: |
| JSON request envelope | 256 KiB |
| DSL source | 32 KiB, 500 lines, 2 KiB per line |
| JSON fixture | 64 KiB, 16 levels, 2,000 values |
| Object / array | 100 keys / 200 items |
| AST | 2,000 nodes, 24 levels |
| Modifiers | 16 per view |
| Render | 500 views, 250 total loop iterations, 20,000 operations |
| Cumulative rendered text | 192 KiB |
| HTML output | 256 KiB |

Operation counters are deterministic and do not use asynchronous Ruby timeouts. Errors return bounded structured diagnostics without backtraces or server paths. The client assigns request revisions, cancels obsolete requests, and refuses to let a stale response replace a newer preview.

Local persistence stores only source or fixture facets the user actually changed. Untouched bundled examples therefore move to their latest shipped revision automatically, while edited drafts continue to survive example updates. Storage schemas use versioned keys, and older keys are left intact rather than destructively rewritten.

This sandbox is designed for local/development showcase use. A host that exposes it outside a trusted development environment should also add its normal authentication, authorization, request-rate, and perimeter body-size controls.
