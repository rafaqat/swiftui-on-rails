# Semantic language architecture

SwiftUI Rails aims to provide a small, expressive, versioned semantic UI
language for Rails and the web. Correctness is the goal. Familiar SwiftUI
vocabulary is useful where it communicates portable intent, but reproducing
every Apple API one-for-one is not a goal.

This direction keeps the language:

- correct by making invalid composition, values, identity, and unsafe behavior
  deterministically rejectable;
- LLM-friendly by exposing one finite, machine-readable vocabulary;
- token-efficient by preferring semantic operations over utility chains and by
  omitting low-level escape hatches from the default generation contract;
- durable by treating canonical DSL, fixtures, versions, and executable
  expectations as the artifacts, rather than preserving a prompt.

The architecture now has two explicit IR layers. The browser playground owns
an authoring IR for inert source, expressions, control flow, and diagnostics.
The gem owns `SwiftUIRails::RenderIR`, the resolved semantic view tree used by
trusted application components, the playground, linting, and the HTML backend.
They solve different problems and neither replaces the durable DSL source.

## One cognitive model

Ruby and RenderIR are the complete application programming model. Product
state, actions, bindings, navigation, presentation, focus, gestures, tasks,
and workflow behavior must be declared through the semantic DSL and survive as
validated RenderIR. Application code must not define Stimulus controllers,
JavaScript event handlers, controller targets, DOM selectors, or direct DOM
mutations.

The gem may ship a small browser runtime, but that runtime is a fixed,
application-agnostic protocol interpreter. It delegates declared events,
transports signed payloads to Rails, validates responses, applies keyed patch
operations, preserves native browser editing state, and executes only
allowlisted semantic browser commands. It must not import application modules,
own domain state, or dispatch arbitrary controller/method strings. A missing
behavior is a language-design task across catalogue, validation, IR, rendering,
runtime command handling, and tests—not permission to add application
JavaScript.

## Two related languages

Keep these boundaries explicit:

1. Trusted application components use the full Ruby SwiftUI Rails DSL. They
   may use normal Ruby, Rails helpers, extracted components, props, state, and
   application-owned `appearance` styles.
2. Browser-submitted playground source uses a much smaller Ruby-shaped
   language. It cannot call arbitrary Ruby, helpers, components, attributes,
   URLs, raw HTML, `.tw`, or `appearance`.

The playground language should never grow merely because trusted component
Ruby can express something. A feature belongs at the untrusted boundary only
when its arguments, composition, resource use, accessibility behavior, and
security effects can be described and validated deterministically.

## One language catalogue

`Showcase::Playground::LanguageCatalog` is the machine-readable source of
truth for playground authoring. It publishes:

- the language and catalogue-schema versions;
- builders, modifiers, statements, and expressions;
- positional and keyword arguments, types, defaults, ranges, and finite enums;
- block contracts, legal parents, and legal modifier targets;
- availability, security notes, resource limits, and the browser-playground
  profile;
- a `semantic` or `escape_hatch` tier for every modifier.
- the Ruby/RenderIR application-authority policy and forbidden JavaScript,
  Stimulus, and DOM-controller contracts.

The compiler derives its accepted call shapes from the catalogue, and the
renderer derives its finite presentation enums from the same types. Editors
and documentation can use the full frozen JSON-native document:

```ruby
catalog = Showcase::Playground::LanguageCatalog.to_h
version = Showcase::Playground::LanguageCatalog::VERSION
button = Showcase::Playground::LanguageCatalog.builder(:button)
text_style = Showcase::Playground::LanguageCatalog.modifier(:text_style)
```

Generation uses the compact contract:

```ruby
semantic_contract = Showcase::Playground::LanguageCatalog.for_generation
complete_contract = Showcase::Playground::LanguageCatalog.for_generation(
  include_escape_hatches: true
)
```

The default deliberately excludes low-level presentation modifiers. A model
normally needs `text_style(:supporting)`, `background_style(:surface)`, and
`button_style(:bordered)`, not every possible color, size, border, and spacing
combination. Editors may still expose supported escape hatches through the full
catalogue.

Compactness is accepted only after semantic coverage. The catalogue's
`generation_contract_omissions` comparison checks that the compact contract
preserves validity-affecting argument shapes, referenced types and constraints,
block contracts, legal parents and targets, modifier tiers, and expression
shapes in the selected generation profile. Descriptions, availability and
security prose, defaults, and block-content descriptions may be omitted because
they do not change whether a candidate is executable; an omitted executable
constraint fails the context-efficiency gate even if the compact document is
smaller.

## Authoring IR and resolved RenderIR

The browser language keeps its source-oriented
`swift-ui-rails.playground-ir`. It can represent `if`, `for_each`, fixture
lookups, and unevaluated builder arguments without executing submitted Ruby.

After the fixed evaluator resolves that document against bounded fixture data,
it builds the same gem-owned `swift-ui-rails.render-ir` document as a trusted
`swift_ui` component. Trusted components reach RenderIR by executing their Ruby
block once against recording builders. Both paths then use the same domain
validator and IR-native ActionView renderer:

```text
trusted component Ruby --execute once--+
                                      +-> resolved RenderIR -> validate -> HTML
playground source -> authoring IR -----+
                    + bounded fixture evaluation
```

`RenderIR::Document`, `Node`, and `Modifier` are immutable, versioned,
canonical JSON-native records. Child and modifier arrays preserve order;
object keys serialize canonically. Nodes retain semantic builder kind,
identity, accessibility metadata, resolved web props, and ordered modifiers.
Invalid schemas, versions, shapes, cycles, depths, non-finite numbers,
executable objects, Symbols as values, and `SafeBuffer` instances fail with an
exact JSON-style path.

Already-rendered ViewComponent buffers and server action closures do not enter
the document. A render-scoped capability registry gives those trusted runtime
values process-keyed, content-fingerprinted opaque identifiers and is discarded
after HTML rendering. The keyed fingerprint makes different trusted fragments
compare differently without serializing their HTML or exposing a plain digest
oracle. Environment values likewise remain request/fiber-local. This keeps
serialized IR inert without removing composition with ordinary Rails
components.

Resolved HTML nodes pass a profile-aware attribute policy before rendering.
It rejects active tags, inline event handlers, ambiguous codec shapes,
executable URL schemes, unsandboxed frames, `srcdoc`, and unsafe iframe sandbox
combinations. Rails-style nested `aria:` hashes are also flattened into the
node's accessibility sidecar, so lint and inspection see the semantics emitted
to the browser.

There is no live shadow renderer or renderer feature flag. A request executes
the component block once and renders once through RenderIR. Parity belongs in
tests; rendering both implementations on every request would approximately
double work and would not provide React-style reconciliation.

Reactive JSON updates now use the stable RenderIR identity boundary directly.
The installed framework DOM runtime advertises keyed render-patch protocol v1;
older clients, initial page loads, and Turbo responses retain the complete HTML
contract. For a reactive document, the HTML backend gives every emitted element
a deterministic `data-swift-ui-ir-key`. An explicit semantic identity starts a
stable descendant scope, while unidentified nodes retain positional identity.
Moving a keyed collection item therefore keeps both its key and the keys of its
descendants.

Each complete render also projects a capability-free patch tree. Its random
baseline token stays inside the encrypted, one-time component snapshot rather
than becoming a browser-controlled field. The server stores the tree briefly
under a digest of that token, bound to component id, component class, and the
same authorization context as the reactive capability. Cached trees omit HTML,
snapshot and stream tokens, render actions, and request-local trusted-content
capabilities.

On the next negotiated update, the normal single RenderIR/HTML render produces
the new tree and a bounded diff emits only `attributes`, `text`, `remove`,
`insert`, `move`, or `replace` operations. Child reordering uses a
longest-increasing-subsequence pass so a rotation of 1,000 keyed rows requires
one move rather than 1,000 replacements. The server refuses patches above 512
operations or 256 KiB and sends complete HTML whenever the baseline is absent,
the tree is unsafe or ambiguous, the root would need replacement, a budget is
exceeded, or the encoded patch is not smaller than the HTML.

The browser independently validates the protocol, keys, targets, fragments,
attributes, and resource bounds before applying it. Successful operations
mutate only their keyed targets, so unchanged and moved DOM objects retain
their identity; focused controls, selection, and unsent binding values are
restored when a containing node must be replaced. A malformed patch fails
closed and reloads from the canonical full-page contract unless the application
cancels the diagnostic event. The reactive root exposes
`data-swift-ui-render-mode` and `data-swift-ui-patch-operations`, plus before,
after, and error events, for UAT and production instrumentation.

This is selective keyed DOM reconciliation, not a browser virtual DOM. The
server still resolves and renders the complete current component before
planning a patch. The present speedup targets network transfer, HTML parsing,
framework-runtime reconciliation work, focus loss, and browser mutation work; incremental
server-side subtree rendering is a separate future optimization.

The checked-in 1,000-key rotation gate requires one move, a patch below 5% of
the complete HTML, planning below one second, and fewer than 250,000
allocations. In a warmed 21-run development measurement on 2026-07-19, the
planner median was 2.806 ms and 14,059 allocations. The one-operation payload
was 181 bytes versus 76,972 bytes of HTML: 425.26x smaller, or a 99.765%
transfer reduction. These figures measure patch planning and encoded response
size only; they deliberately do not subtract the preceding server render or
claim a browser frame-time result.

Performance is an executable contract, not an assumption. The checked-in
1,000-flat-text-node gate compares fresh one-pass IR and preserved legacy
contexts using median CPU time and allocations, with both absolute and relative
ceilings. On the 2026-07-19 development baseline, the optimized IR path measured
5.81 ms and 41,025 allocations versus 1.80 ms and 10,006 allocations for the
legacy direct renderer (3.23x CPU and 4.10x allocations). That is materially
better than the first IR pass (14.37 ms and 157,071 allocations), but it is not
claimed as React-style client reconciliation.

The runtime API is intentionally small:

```ruby
component = ProductRowComponent.new(product: product)
html = ApplicationController.render(component, layout: false)

document = component.last_render_ir
SwiftUIRails::RenderIR::Validator.validate!(document)
json = document.canonical_json
```

`last_render_ir` is development/test introspection, not persisted application
state. A document containing opaque trusted capabilities can be inspected and
serialized but can only be rendered by the request-local session that owns
those capabilities.

Reactive components put their stable reactive container in the same document,
so `last_render_ir` describes the complete component output rather than an
inner fragment later wrapped by string interpolation.

## Compilation and validation phases

The browser language has explicit stages rather than letting source drive the
renderer directly:

```text
View.rb -> Prism syntax -> SourceCompiler -> authoring IR
                                           |
LanguageCatalog ---------------------------+-> SemanticValidator
                                                   |
Data.json -> bounded FixtureParser ----------------+-> fixed evaluator
                                                           |
                                                    resolved RenderIR
                                                           |
                                             RenderIR::Validator -> HTMLRenderer
```

The stages have different responsibilities:

1. `SourceCompiler` accepts only the supported syntax tree and emits a
   `swift-ui-rails.playground-ir` document. Ruby execution is not involved.
2. `IntermediateRepresentation` normalizes JSON-native data, freezes it, gives
   nodes typed traversal wrappers, and provides deterministic serialization.
   The IR schema version is independent from the language version.
3. `SemanticValidator` checks document/version compatibility, node shapes,
   argument types, required values, legal parents and modifier targets, scope,
   stable collection identity, and expression structure.
4. `Renderer` accepts validated authoring IR and fixture values through fixed
   handlers and bounded evaluation, lowering them to gem-owned RenderIR.
   Every `for_each` item identity is carried into the resolved tree and a
   digest-backed DOM morph identity; reordering preserves keys, multiple roots
   get stable ordinals, and nested loops include their parent ancestry.
5. `RenderIR::Validator` enforces the resolved renderer contract, and
   `RenderIR::HTMLRenderer` emits escaped ActionView HTML without re-running
   source, component Ruby, or DSL blocks.

Separating these phases lets syntax evolve without silently changing rendering
semantics, lets persisted artifacts declare their compatibility boundary, and
lets tools validate inert IR without evaluating source.

## Diagnostics and fixes

Rejections are part of the language API. A diagnostic uses a stable code and
domain wording, with source coordinates and an IR path where available:

```json
{
  "source": "view",
  "severity": "error",
  "code": "modifier_incompatible",
  "message": "Modifier `button_style` cannot be applied to `text`.",
  "line": 1,
  "column": 14,
  "path": "$.root.modifiers[0]",
  "hint": "Apply `button_style` to a button view.",
  "fix": { "kind": "remove", "path": "$.root.modifiers[0]" }
}
```

Fixes are bounded `add`, `replace`, or `remove` operations against semantic IR;
they are not Ruby patches to execute. Consumers should branch on `code`, use
`message` for people, and treat `hint` and `fix` as optional assistance.
Changing prose does not require a language version bump, but changing the
meaning of a code or fix does.

## Canonical source and durable artifacts

`SourceFormatter` compiles and semantically validates source before emitting
one canonical textual form. It recompiles that output and compares semantic IR
without source locations, so formatting cannot silently alter the view.

A successful `Runner` result includes:

- `canonical_source`;
- a versioned playground artifact containing the canonical DSL and fixture;
- language, catalogue-schema, and versioned-IR metadata;
- a digest of the semantic IR; and
- executable compile, accessibility-intent, and security-profile expectations.

Prompts, assistant-contract fingerprints, generated HTML, and trusted persisted
IR are intentionally absent. Prompt wording and token optimisation can change
without invalidating a durable DSL artifact.
Artifact compatibility is therefore governed by the saved language,
catalogue-schema, IR, fixture, source, and executable test contracts—not by the
current `AssistantContract` version or fingerprint. Changing assistant
instructions or provider settings alone does not require rewriting or
invalidating an artifact.
`ArtifactVerifier` validates the exact language and test contracts, reparses
the bounded fixture, recompiles the saved DSL, validates it against the current
catalogue and IR version, and checks the semantic digest. When supplied a view
context it also renders the fixture, catching runtime data and collection
identity failures. The checked-in DSL is therefore authoritative and remains
reviewable without a model provider.

```ruby
result = Showcase::Playground::Runner.call(
  source: source,
  data_json: data_json,
  view_context: ApplicationController.new.view_context
)

File.write("product-card.playground.json", result.artifact.to_json) if result.success?

verification = Showcase::Playground::ArtifactVerifier.call(
  File.read("product-card.playground.json"),
  view_context: ApplicationController.new.view_context
)
raise verification.diagnostics.inspect unless verification.success?
```

Host applications should choose their own storage and authorization policy.
The example above illustrates the object contract; browser-supplied paths must
never be passed to `File.write` or `File.read`.

## Provider-neutral assistant loop

`AssistantSession` coordinates a bounded, provider-neutral loop:

```text
instruction + fixture + optional current DSL
  -> generator
  -> compile + semantic validation + render
  -> domain diagnostics on failure
  -> generator repair
  -> canonical DSL and preview on success
```

The session provides `AssistantContract`, including the compact generation
catalogue, and requires one complete DSL source document with no Markdown or
explanation. It performs at most three attempts. Every candidate passes through
the same runner as a manual edit; model output is never trusted or evaluated as
Ruby.

The showcase does not depend on a particular model SDK. Configure a server-side
callable that accepts `messages:` and `response:` and returns either a DSL
String or an object responding to `source`:

```ruby
# app/services/playground_model_generator.rb
class PlaygroundModelGenerator
  def initialize(client:)
    @client = client
  end

  def call(messages:, response:)
    @client.generate(
      messages: messages,
      output: response.fetch(:contract),
      max_bytes: response.fetch(:max_bytes)
    )
  end
end

# config/initializers/playground_assistant.rb
Rails.application.config.x.swift_ui_playground.generator =
  PlaygroundModelGenerator.new(client: Rails.application.config.x.model_client)
```

The adapter owns provider authentication, timeouts, retries, rate limits,
logging/redaction, and extraction of plain DSL text. Provider credentials stay
on the server. When no callable is configured, the assistant endpoint returns
the structured `assistant_unavailable` error; manual compilation remains fully
available.

## Showcase HTTP API

These development/showcase routes expose the workbench contract:

| Method and path | Purpose |
| --- | --- |
| `GET /showcase/playground/language` | Full catalogue, compact generation contract, fingerprint, and IR versions |
| `POST /showcase/playground/compile` | Compile source and fixture JSON; return diagnostics, canonical source, preview, metrics, and artifact |
| `POST /showcase/playground/assist` | Run the configured generate/validate/repair adapter |
| `POST /showcase/playground/verify` | Recompile and verify an exported artifact |
| `GET /showcase/playground/reliability` | Execute the fixed reliability corpus and return its report |

POST requests are normal Rails same-origin requests and require the session's
CSRF token. They are not tokenless `curl` APIs. The Playground declares compile
and assistant commands in Ruby; the gem runtime owns their CSRF-aware browser
transport. Applications must not reproduce that transport with a custom fetch
wrapper or DOM controller. Server-side CI and editor integrations should call
the Ruby contracts or tasks below rather than scraping a browser token.

The endpoints inherit the playground's deterministic body and source limits.
They are reference development APIs, not an authentication boundary. A host
exposing them beyond local development must add authorization, rate limiting,
provider budget controls, and its normal perimeter request limits.

The same contracts are available without HTTP for CI and editor tooling:

```bash
bin/rails swift_ui:language:manifest COMPACT=1
bin/rails swift_ui:playground:format SOURCE=View.rb
bin/rails swift_ui:artifact:verify ARTIFACT=View.swiftui-rails.json
bin/rails swift_ui:reliability:report
```

## Fixed reliability corpus

`ReliabilityCorpus` pins executable accept, reject, identity, adversarial, and
golden-repair cases. `ReliabilityEvaluator` runs each recorded source and
fixture through the real `Runner`, not a mock parser. The corpus `prompt` labels
the intended task, but this deterministic evaluator does not submit that prompt
to `AssistantSession` or any provider. Its report therefore declares
`measurement_scope: recorded_candidate_language_conformance` and
`model_prompt_execution: not_run_without_provider`, and includes:

- total cases, passed cases, and `expectation_rate` for correct acceptance or
  rejection of the recorded candidates;
- `recorded_acceptances`, `recorded_valid_cases`, `recorded_candidates_valid`, and
  `recorded_candidate_validity_rate` for checked-in candidates expected to be
  accepted;
- `semantic_snapshot_cases`, `semantic_snapshots_passed`, and
  `semantic_snapshot_accuracy` from required and forbidden HTML fragments;
- `golden_repair_cases`, `golden_repairs_checked`,
  `golden_repairs_passed`, and `golden_repair_contract_rate` for checked-in
  replacement source or fixture data;
- `accessibility_cases`, `accessibility_passed`, and `accessibility_rate`;
- `unsafe_construct_cases`, `unsafe_constructs_rejected`,
  `unsafe_construct_rejection_rate`, and the compatibility count
  `security_rejections`; and
- full-catalogue versus compact-context bytes, clearly labelled
  `ceil(bytes/4)` token estimates and reduction rates, plus
  `executable_constraints_preserved` and
  `omitted_executable_constraints` semantic-coverage evidence.

The compact context passes only when it is smaller than the full catalogue and
the semantic-coverage comparison finds no omitted executable constraint. Byte
or estimated-token reduction by itself is not a correctness result.

Case-level HTML expectations pin accessible semantic output such as announced
status content, while adversarial cases pin rejection of execution and class
injection. Browser accessibility, CSP, dependency, and penetration tests remain
release gates; the synchronous assistant loop does not claim to replace them.

The deterministic corpus measures recorded-candidate conformance and whether
known golden repairs satisfy declared intent fragments. It does not measure a
model's first-pass validity, ability to choose a repair, or preservation of
natural-language intent. The built-in report therefore leaves
`model_first_pass_validity_rate` and `model_repair_rate` as `null`; merely
configuring the optional generator does not make this deterministic route a
provider run. A separate model evaluation must execute each prompt through
`AssistantSession`, record every generated candidate and repair attempt, and
capture the provider, model, parameters, assistant-contract fingerprint, and
language version so results remain comparable.

## Admitting and versioning features

A new playground feature should be admitted only when it:

1. expresses recurring product or web intent more clearly than existing
   composition;
2. has bounded, machine-readable arguments and legal composition;
3. preserves semantic HTML, accessibility, progressive enhancement, and Rails
   authorization boundaries;
4. has domain diagnostics, canonical formatting, corpus coverage, and security
   rejection tests;
5. reduces or justifies its vocabulary and generation-token cost.

Prefer a reusable semantic builder or modifier over several presentation
tokens. Keep a low-level operation as an explicit escape hatch when necessary,
and exclude it from constrained generation by default.

Version boundaries are deliberate:

- bump the language version for incompatible vocabulary or semantic changes;
- bump the IR version for an incompatible document-shape change;
- bump the assistant contract version when model instructions or response
  semantics change;
- update deterministic reliability expectations when language behavior changes,
  and provider-evaluation baselines when assistant behavior changes;
- regenerate durable artifacts only when their canonical DSL, fixture,
  language, IR, or executable test contract changes. Assistant prompt or
  contract changes alone do not invalidate them.

The SwiftUI compatibility matrix informs naming and honest web mappings. It is
not a backlog requiring parity with Apple's compiler, runtime, or annual API
surface.
