# DSL Authoring Guide

The canonical rules for writing SwiftUI Rails components — for humans and for
LLM agents. Where other documents disagree with this one, this one wins.
Validate what you write with the harness:

```bash
bin/rails swift_ui:lint FILE=app/components/foo_component.rb   # FORMAT=json for agents
echo 'vstack { text("hi") }' | bin/rails playground:compile     # playground grammar
```

Both emit domain-phrased diagnostics with line/column and repair hints; lint
exits non-zero on errors. Lint parses modifier chains, renders every registered
component and story fixture through resolved RenderIR, validates and
canonical-JSON round-trips that document, and checks emitted classes against
the compiled Tailwind build plus framework semantic stylesheets. Duplicate
missing-class warnings are collapsed per source file. Missing fixtures and
components that bypass RenderIR are errors rather than skipped diagnostics.
Strict CSS is scoped to the current lint execution, so concurrent requests do
not observe a global configuration change.

For browser-submitted source, the versioned
`Showcase::Playground::LanguageCatalog` is the executable vocabulary—not the
larger trusted Ruby API described throughout this guide. Give generators
`LanguageCatalog.for_generation`, which excludes presentation escape hatches
by default, and return their output to the compiler/semantic validator rather
than executing it. See [Semantic language architecture](semantic_language_architecture.md)
for the IR, canonical artifact, provider adapter, and reliability contracts.

## The one cognitive model

All application state and behavior is authored in Ruby and must be representable
in RenderIR. Declare interactions with SwiftUI Rails state, binding, action,
navigation, presentation, focus, gesture, task, and workflow APIs. The
gem-owned browser runtime only interprets that allowlisted protocol and applies
keyed patches.

Do not create Stimulus controllers, targets, or actions; do not emit
`data-controller`, `data-action`, `data-*-target`, inline handlers, controller
method strings, DOM selectors, or application-specific JavaScript. Direct DOM
code merely recreates a second state and behavior model under another name. If
the DSL cannot describe a required browser behavior, extend the semantic
catalogue, validator, RenderIR, renderer, runtime command allowlist, and tests as
one framework feature before using it in application code.

## The styling decision ladder

Choose the **highest** rung that expresses your intent; drop down only
deliberately:

1. **Semantic roles** — product meaning, theme-aware, portable:
   `text_style(:headline)`, `font(:title2)`, `foreground_style(:secondary)`,
   `background_style(:surface)`, `badge("Live", tone: :success)`,
   `button_style(:primary)`, `.appearance(:deployment_card)` for app-specific
   visuals (CSS owns the implementation).
2. **Named literal modifiers** — validated palette/scale values:
   `.bg("blue-500")`, `.text_color("slate-600")`, `.p(4)`, `.rounded("2xl")`,
   `.font_weight("bold")`, `.shadow("md")`. Values come from the validated
   vocabulary (see `SwiftUIRails::Security::CSSValidator`); unknown values
   raise in strict mode.
3. **`.tw("…")`** — the escape hatch for application-owned utilities,
   arbitrary values, and variant-prefixed classes (`hover:`, `sm:`,
   gradients). Unvalidated by design: anything here must appear in the
   compiled Tailwind build or it silently renders unstyled — `swift_ui:lint`
   warns when it doesn't.

Never smuggle multiple classes through a value slot (`bg("gradient-to-br
from-…")` is wrong; use `.tw`). One intent, one call.

## Canonical vocabulary (synonyms are removed, do not reintroduce)

| Intent | Canonical | Removed/avoid |
|---|---|---|
| Background | `.bg("blue-500")` | `.background` (hex-only niche), smuggled `.tw` colors |
| Hover background | `.hover_bg("gray-100")` | `hover_background` (deleted) |
| Full width | `.w_full` | `full_width` (deleted), `width("full")` (never existed) |
| Text size | `.text_size("xl")` or `font(:headline)` | duplicate `font_size` def (deleted; alias remains) |
| Grid | `grid(columns: 3, spacing: 12)` | `cols:`/`gap:` (raise ArgumentError) |
| Link | `link("Label", destination: path)` for validated URLs; `a(href:)` for blocks | — |
| Insertion/removal animation | `.transition(insertion: :move_up, removal: :opacity)` | hand-rolled enter/exit JS |
| Value-driven animation | `.animation(value: component.count)` | gesture-scoped grammars |

## Props and state

- Props: `prop :name, type: String, required: true` / `default:`. Prop names
  share a namespace with rendering internals — never name a prop `tag`,
  `label`, `title`, `style`, or any DSL element/modifier name.
- Inside `swift_ui do … end`, capture the component first when you need props
  in nested blocks: `component = @component`, then `component.count`. Bare
  prop reads work at the top level but shadowing DSL names (e.g. a `label`
  prop) resolves to the DSL element instead — the capture avoids the trap.
- Element-building helper methods must be called **bare** (`header_row`),
  not via `component.header_row` — delegation wires the DSL context.
- State ownership: server-owned `state`/`binding` with signed action round
  trips is the interaction model. Latency-sensitive ephemera such as palette
  filtering, drag previews, and keyboard navigation must use bounded semantic
  commands represented in RenderIR, never an application controller.

## Composition

- `render ChildComponent.new(...)` inside DSL blocks composes children —
  including inside `.each` loops.
- Collections: `Component.with_collection(items)` (declare
  `with_collection_parameter`; surface the keyword in `initialize` when the
  prop system's catch-all hides it).
- Native semantics first: `table/thead/tr/th/td`, `dialog`, `details` via
  `disclosure_group`, real `<a>`/`<form>` — progressive enhancement is the
  floor, and the framework runtime only accelerates declared semantics.

## Icons and content

- `icon("check", size: 14)` — allowlisted glyph names only; unknown names
  raise and enumerate the vocabulary. Custom art: `image()` with an SVG
  asset.
- `chart`/`canvas`/`map` are static and accessible by design; interactivity is
  declared through bounded RenderIR gestures and commands (see
  `/demos/dispatch`).

## Error contract (what validators promise you)

Every rejection is phrased at the domain level and enumerates the valid
vocabulary where finite: `unknown transition: :teleport (expected one of
opacity, move_up, move_down, scale, blur)`; unknown modifiers get
did-you-mean suggestions. If you hit a bare stack trace where a domain error
should be, that is a bug worth fixing at the source.
