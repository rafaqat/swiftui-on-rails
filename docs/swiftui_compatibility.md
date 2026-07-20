# SwiftUI compatibility contract

SwiftUI Rails is SwiftUI-inspired; it is not an implementation of Apple's SwiftUI framework. This document defines the boundary precisely enough for maintainers, users, and tests to make the same compatibility claims.

The current baseline is the **SwiftUI 2027 releases announced at WWDC26, built with Xcode 27**, reviewed on 18 July 2026. Apple describes these APIs as subject to change, so the baseline should be reviewed again when the final SDKs ship.

## How to read the contract

Compatibility and delivery are separate axes:

- `supported`: a first-class gem API preserves the portable SwiftUI intent on the web.
- `partial`: a first-party API exists, but has narrower or different semantics.
- `web_equivalent`: Rails or browser behavior is intentionally the equivalent; native API parity is not the goal.
- `not_applicable`: the feature belongs to Apple's compiler, operating systems, hardware, or native host lifecycle.

Delivery means:

- `available`: implemented and suitable within the stated web contract.
- `prototype`: implemented experimentally, with known semantic or lifecycle gaps.
- `planned`: specified here, but not implemented as a first-class gem API.
- `not_applicable`: no gem implementation is intended.

An entry marked `web_equivalent` and `planned` is a design decision, not a claim that the feature already exists. An entry marked `partial` and `available` is usable within its stated limits, not a parity claim.

## Product direction: semantic correctness, not API count

This matrix is a compatibility boundary, not a requirement to translate every current or future SwiftUI API into Ruby. The product goal is a small, expressive, versioned semantic UI language that makes incorrect Rails and web interfaces difficult for both people and LLMs to express.

A SwiftUI name should enter the portable language only when it captures recurring intent and has honest Rails/browser semantics. Its arguments, composition, accessibility behavior, progressive-enhancement fallback, security effects, and resource use must be deterministically testable. Otherwise the feature should be composed from existing primitives, implemented as an application component or validated `appearance`, classified as a narrower web equivalent, or marked not applicable.

The browser playground makes this policy executable through a machine-readable `LanguageCatalog`, source-oriented authoring IR, gem-owned resolved RenderIR, separate syntax and semantic validation, domain diagnostics and bounded fixes, canonical source artifacts, and a fixed reliability corpus. Its compact generation contract excludes low-level presentation escape hatches by default. Trusted components and playground previews converge on the same validated, IR-native HTML backend. This improves correctness and token efficiency while preventing Apple's much larger API surface from becoming an accidental LLM vocabulary. See [Semantic language architecture](semantic_language_architecture.md).

The executable source of truth is `SwiftUIRails::Compatibility`:

```ruby
SwiftUIRails::Compatibility.fetch(:bindings)
SwiftUIRails::Compatibility.select(delivery: :planned)
SwiftUIRails::Compatibility.summary
SwiftUIRails::Compatibility.validate!
```

## Semantic styling boundary

`font`, `foreground_style`, `background_style`, and `text_style` form a finite, role-based design-system layer. They let product code say `text_style(:supporting)` or `foreground_style(:danger)` while stable renderer classes and CSS custom properties own the current visual treatment.

- Font roles: `large_title`, `title`, `title2`, `title3`, `headline`, `subheadline`, `body`, `callout`, `footnote`, `caption`, and `caption2`.
- Foreground roles: `primary`, `secondary`, `tertiary`, `quaternary`, `accent`, `success`, `warning`, `danger`, and `on_accent`.
- Background roles: `canvas`, `surface`, `elevated`, `muted`, `accent`, `success`, `warning`, and `danger`.
- Composite text styles: `title`, `headline`, `body`, `supporting`, `metadata`, and `caption`.

The composite mappings are `title` → title/primary, `headline` → headline/primary, `body` → body/primary, `supporting` → subheadline/secondary, `metadata` → footnote/tertiary, and `caption` → caption/secondary.

Each category is deterministic and last-call-wins. `text_style` sets both a font role and a foreground role; a later explicit `font` or `foreground_style` overrides its corresponding facet, while a later `text_style` resets both. Literal `text_color` and `bg` share the foreground and background modifier slots, so they deterministically replace an earlier semantic role and are themselves replaced by a later semantic call. `.text_size` and `.tw` remain deliberate web escape hatches. This is therefore a supported application abstraction with partial SwiftUI compatibility: it preserves semantic role intent, but does not claim arbitrary `ShapeStyle`, Apple font metrics, or platform Dynamic Type behavior.

The default tokens follow the browser's light or dark preference and higher-contrast preference. An application may set `data-swift-ui-theme="light"` or `data-swift-ui-theme="dark"` on a container for an explicit subtree, and may override the documented `--swift-ui-*` custom properties to supply its own visual language.

`appearance(name)` covers application-defined presentation that does not belong in the portable role catalog. It accepts a safe String or Symbol identifier, normalizes underscores to kebab case, and emits one `data-swift-ui-appearance` hook for application CSS. It cannot carry utility lists, selectors, or arbitrary CSS. `visually_hidden` supplies the framework-owned accessible hiding treatment and can be reversed with `visually_hidden(false)`. Together these APIs preserve semantic component intent while leaving browser-specific implementation in CSS; they are a narrower web analogue of custom `ViewModifier` composition, not Swift generic or environment-driven style protocols.

## Feature matrix

| Feature ID | Category | SwiftUI capability | Compatibility | Delivery | Rails/web contract and remaining gap |
| --- | --- | --- | --- | --- | --- |
| `declarative_blocks` | `declarative_layout` | Result-builder view composition | `supported` | `available` | Ruby blocks execute once into immutable resolved RenderIR, then the IR-native backend emits HTML in declaration order. |
| `stack_layouts` | `declarative_layout` | VStack and HStack | `supported` | `available` | Flexbox-backed vertical and horizontal stacks support alignment and spacing. |
| `overlay_layout` | `declarative_layout` | ZStack | `supported` | `available` | A single-cell CSS Grid overlays direct children and supports the documented alignment values. |
| `basic_views_and_controls` | `declarative_layout` | Text, Image, Button, Link, and form controls | `supported` | `available` | Semantic HTML elements are produced with chainable attributes and modifiers. |
| `grid_layout` | `declarative_layout` | Grid | `supported` | `available` | CSS Grid provides finite responsive grid composition. |
| `lazy_containers` | `declarative_layout` | LazyVGrid and lazy stacks | `partial` | `prototype` | The DSL exposes grid syntax but currently renders the complete HTML collection. Gap: There is no viewport-driven DOM virtualization or incremental materialization. |
| `conditional_composition` | `declarative_layout` | Conditional and repeated content in builders | `supported` | `available` | Ruby `if`, `case`, and `Enumerable` iteration compose directly inside DSL blocks. |
| `modifier_chains` | `modifiers_composition` | View modifiers | `partial` | `available` | Element modifiers lower semantic appearance and interaction declarations into validated RenderIR; application controller metadata is not part of the model. Gap: The catalog is a web-focused subset; typed environment propagation is an explicit server render scope rather than an implicit property-wrapper runtime. |
| `component_props` | `modifiers_composition` | View inputs | `supported` | `available` | Components declare typed, required, defaulted, and validated props. |
| `component_slots` | `modifiers_composition` | Content closures and builder parameters | `supported` | `available` | Named single or collection slots accept captured component content. |
| `collection_composition` | `modifiers_composition` | ForEach-style reusable collection rendering | `supported` | `available` | ViewComponent collection rendering and DSL collection helpers render server-owned collections. |
| `semantic_views_and_controls` | `modifiers_composition` | ProgressView, Gauge, ControlGroup, DisclosureGroup, Menu, DatePicker, ColorPicker, and Stepper | `supported` | `available` | Semantic HTML progress, meter, details, fieldset, and input elements preserve browser and assistive-technology behavior. |
| `status_badges` | `modifiers_composition` | Reusable semantic status view composition | `web_equivalent` | `available` | A tone-based badge owns repeated status styling and can opt into an announced ARIA status. |
| `semantic_control_styles` | `modifiers_composition` | ButtonStyle, LabelStyle, and control style roles | `partial` | `available` | Allowlisted button styles and sizes map semantic names to an enforced web design-system contract. Gap: The catalog is intentionally smaller than SwiftUI's environment-driven control and label style protocols. |
| `semantic_text_styles` | `modifiers_composition` | Font text styles, foregroundStyle, and backgroundStyle | `partial` | `available` | Allowlisted font, foreground, background, and composite text roles map application vocabulary to stable design tokens instead of exposing a Tailwind palette at every call site. Gap: The portable role catalog does not reproduce arbitrary ShapeStyle values, custom fonts, gradients, or Apple's platform-specific Dynamic Type metrics. |
| `custom_view_appearances` | `modifiers_composition` | Custom ViewModifier composition | `partial` | `available` | A validated appearance identifier separates application intent from CSS implementation, while visually_hidden provides framework-owned accessibility-preserving presentation. Gap: CSS remains the platform implementation; the hook is not a generic Swift ViewModifier type or an environment-driven style protocol. |
| `animation_and_transition` | `modifiers_composition` | Value-driven animation and transitions | `partial` | `available` | Allowlisted value-associated CSS transitions and content-transition metadata respect reduced-motion preferences. Gap: CSS transitions do not reproduce SwiftUI transactions or an insertion/removal transition lifecycle. |
| `accessibility_semantics` | `modifiers_composition` | Accessibility modifiers | `partial` | `available` | Semantic HTML plus bounded, allowlisted ARIA modifiers express labels, values, hints, roles, live regions, headings, identifiers, traits, and state. Gap: Custom accessibility actions, rotors, and Apple-platform assistive-technology APIs remain outside the browser contract. |
| `local_state` | `data_flow` | State | `partial` | `available` | Typed component-local state survives authorized server round trips in a one-time encrypted snapshot and is renewed after each render. Gap: State lifetime follows the rendered component and request/capability cycle rather than SwiftUI view identity and transactions. |
| `bindings` | `data_flow` | Binding and projected values | `partial` | `available` | Typed root bindings round-trip through native input, checkbox, and select metadata; getter/setter mapping and projection remain server-local compositions. Gap: Mapped and projected bindings are not independent browser transport roots, and arbitrary client controls need an application adapter. |
| `observation` | `data_flow` | Observable and observed models | `web_equivalent` | `available` | Observed resources reload authoritative server data after opaque Action Cable invalidations; thread-safe ObservableStore supports in-process coordination. Gap: Invalidation is resource-scoped rather than SwiftUI property-access dependency tracking, and ObservableStore is not a distributed datastore. |
| `environment_values` | `data_flow` | Environment and EnvironmentValues | `web_equivalent` | `available` | Fiber/request-scoped immutable contexts carry typed, inheritable server values without serializing private context into HTML. |
| `reactive_rendering` | `data_flow` | Automatic view updates after data changes | `web_equivalent` | `available` | One-time encrypted, authorization-bound component snapshots renew through serialized HTTP updates; read-only Action Cable invalidations request an authoritative rerender. |
| `task_lifecycle` | `data_flow` | `task` and `refreshable` | `web_equivalent` | `available` | DOM connect/disconnect owns lifecycle events and cancellable same-origin browser tasks with explicit loading, success, failure, and refresh events. |
| `navigation_stack` | `navigation_interaction` | NavigationStack, NavigationPath, and navigationDestination | `web_equivalent` | `available` | Labelled navigation landmarks and validated real anchors delegate paths, deep links, history, and Turbo visits to Rails and the browser. Gap: There is intentionally no second in-memory NavigationPath or typed destination registry beside Rails routes. |
| `presentation` | `navigation_interaction` | sheet, popover, fullScreenCover, and presentation modifiers | `web_equivalent` | `available` | Native dialog and details elements provide sheet/popover presentation with same-origin route fallbacks, focus handling, and server-owned state. Gap: Native full-screen covers, detents, and Apple presentation-controller behavior have no direct browser equivalent. |
| `alerts_and_dialogs` | `navigation_interaction` | alert and confirmationDialog | `web_equivalent` | `available` | Accessible alertdialog builders pair native dismissal with ordinary server-authorized Rails actions and optional item-driven state. |
| `gestures` | `navigation_interaction` | Tap, hover, keyboard, drag, magnification, and composed gestures | `partial` | `available` | Accessible tap and long-press activation, filtered key presses, and value-producing pointer or opt-in keyboard drag events are bounded RenderIR commands interpreted by the gem runtime. Gap: Recognizer composition, rotation, magnification, and transferable drag-and-drop remain outside this gesture slice. |
| `focus` | `navigation_interaction` | FocusState and focus scopes | `partial` | `available` | Reactive FocusState expresses next-render focus intent while native `activeElement`, scoped events, and semantic tab stops own live browser focus. Gap: Live `activeElement` changes intentionally remain client-owned and advanced route-level restoration and focus-section traversal are not implemented. |
| `drag_and_drop` | `navigation_interaction` | Transferable drag and drop | `web_equivalent` | `planned` | HTML Drag and Drop and pointer events should map payloads through signed Rails actions. Gap: The available stable-key reorder workflow is intentionally narrower; no general transferable payload or drop-destination API exists. |
| `toolbars` | `navigation_interaction` | toolbar and ToolbarItem placement | `web_equivalent` | `available` | Labelled browser toolbars provide semantic placement hooks, priority-aware responsive overflow, pinned actions, roving focus, and optional scroll minimization. Gap: Placement is a styling/interaction contract, not Apple window-toolbar placement. |
| `charts` | `rich_platform` | Swift Charts | `web_equivalent` | `available` | Bar and line charts render as server-owned accessible SVG with exact values repeated in a hidden data table. Gap: The bounded chart helper does not yet expose Swift Charts' full mark, axis, scale, interaction, or selection model. |
| `maps` | `rich_platform` | MapKit for SwiftUI | `web_equivalent` | `available` | A provider-free schematic SVG coordinate plot renders bounded markers and an accessible exact-coordinate list without contacting a tile provider. This prevents provider-side location disclosure, not client-side exposure: the coordinates are intentionally client-visible presentation data and must already be authorized for the viewing audience. Gap: Street maps, navigation, live location, tiles, and MapKit overlays require a separately selected provider integration. |
| `canvas` | `rich_platform` | Canvas, GraphicsContext, and custom drawing | `web_equivalent` | `available` | A bounded declarative drawing-command vocabulary renders safe SVG with an accessible label and fallback text. Gap: Arbitrary paths, code execution, images, shaders, and high-frequency imperative GraphicsContext drawing are outside this helper. |
| `rich_text` | `rich_platform` | AttributedString and rich Text composition | `web_equivalent` | `available` | Sanitized semantic HTML represents a bounded editorial vocabulary with validated safe links. Gap: This is sanitized document markup, not a mutable AttributedString run model. |
| `web_view` | `rich_platform` | WebView | `web_equivalent` | `available` | A titled, sandboxed iframe embeds allowlisted same-origin or approved external documents with a constrained permission policy. Gap: This is an iframe security boundary, not a native WebView, navigation delegate, cookie jar, or process model. |
| `scenes_and_windows` | `rich_platform` | App, Scene, WindowGroup, and window management | `not_applicable` | `not_applicable` | Rails application boot, routes, requests, and browser tabs own the host lifecycle. Native process, scene session, and window lifecycle parity is outside the gem's scope. |
| `apple_platform_integration` | `rich_platform` | UIKit/AppKit interop, widgets, watch complications, and immersive spaces | `not_applicable` | `not_applicable` | Web integrations use standards-based browser capabilities and Rails adapters. Apple framework and device-host integration requires native application code. |
| `content_builder` | `wwdc26` | ContentBuilder unification and Xcode 27 type-checking improvements | `not_applicable` | `not_applicable` | Ruby blocks already accept heterogeneous DSL content without Swift result-builder type checking. |
| `state_macro` | `wwdc26` | Macro-based State and lazy Observable initialization | `not_applicable` | `not_applicable` | Ruby has no equivalent compile-time macro migration; web state lifetime remains an explicit gem contract. |
| `arbitrary_container_reordering` | `wwdc26` | Reordering in lists, grids, sections, and custom layouts | `web_equivalent` | `available` | Stable-key list, grid, and custom collections expose visible move forms; optional drag submits the same authorized Rails mutation. Gap: The server remains the ordering authority; the client does not provide SwiftUI's in-process collection mutation model. |
| `swipe_actions_container` | `wwdc26` | Swipe actions in arbitrary scroll containers | `web_equivalent` | `available` | Visible, focusable Rails action forms remain authoritative while leading/trailing pointer swipes only reveal and announce the action rail. Gap: Full-swipe execution is intentionally absent because a gesture is not authorization for a server mutation. |
| `toolbar_visibility_and_overflow` | `wwdc26` | Toolbar visibility priority, overflow menu, pinned actions, and minimize behavior | `web_equivalent` | `available` | Toolbar items declare low/automatic/high/pinned priority, automatic/visible/overflow visibility, and optional scroll minimization while preserving a complete no-JavaScript fallback. Gap: Adaptation follows measured browser space rather than Apple toolbar/window placement rules. |
| `document_api` | `wwdc26` | ReadableDocument, WritableDocument, and DocumentCreationSource | `web_equivalent` | `available` | Route-backed import, signed creation provenance, server validation helpers, Active Storage hooks, native progress, and streaming export form a Rails document workflow. Gap: Rails requests, storage, jobs, and browser downloads own lifecycle and persistence rather than native document scenes. |
| `async_image_caching` | `wwdc26` | AsyncImage HTTP caching, URLRequest, URLSession, and URLCache control | `web_equivalent` | `available` | A native `img` keeps browser HTTP caching and decoding authoritative while progressive enhancement exposes loading, success, and failure phases. Gap: Only the browser cache policy is exposed; URLSession, URLRequest, and URLCache are native networking APIs. |
| `item_bound_presentations` | `wwdc26` | Item-binding patterns for alerts and confirmation dialogs | `web_equivalent` | `available` | `sheet`, `alert`, and confirmation dialog derive server-rendered visibility and yielded content from an optional item. Gap: Clearing or replacing the item remains explicit application/server state rather than a client Binding side effect. |
| `liquid_glass_refresh` | `wwdc26` | Automatic refreshed Liquid Glass appearance on Apple 2027 OS releases | `not_applicable` | `not_applicable` | Web applications retain an explicit, product-owned design system rather than adopting an OS material automatically. |

## WWDC26 evidence

The WWDC26 entries above come from Apple's current primary material:

- [WWDC26 SwiftUI guide](https://developer.apple.com/wwdc26/guides/swiftui/)
- [What's new in SwiftUI (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/269/)
- [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui)
- [TN3211: State and ContentBuilder source incompatibilities](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder)
- [SwiftUI documentation](https://developer.apple.com/documentation/swiftui/)

## Updating the matrix

Change the Ruby registry and this table in the same commit. The compatibility tests require every registry feature to appear exactly once here with the same compatibility and delivery values. Mark a planned feature `prototype` only when a callable first-party API exists, and mark it `available` only after its documented web semantics have focused behavioral tests.
