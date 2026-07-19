# React versus SwiftUI Rails token benchmark

The token benchmark answers one narrow question:

> How many `o200k_base` tokens are present in checked-in React-on-Rails and
> SwiftUI Rails reference source written against the same UI contract?

It does not turn source length into a claim about correctness, developer
effort, runtime cost, or model performance. Those require separate evidence.

## Deterministic reference layer

The fixed corpus is versioned and hashed. Each case declares:

- one framework-neutral behavior and accessibility contract;
- one shared serialized fixture;
- one React-on-Rails reference;
- one SwiftUI Rails reference; and
- the parity checks that both implementations must eventually pass.

The report keeps two scopes separate:

1. `view_source` counts the primary authored component source, including its
   imports and local helpers.
2. `authored_production_closure` counts
   the view plus case-owned mount, Rails view, local behavior, styles, and
   build/dependency declarations needed to serve that independent case.

Shared Rails routes, controllers, fixtures, neutral acceptance tests,
framework source, lockfiles, generated bundles, source maps, prompts, and
provider protocol text are excluded. These boundaries are included in the
machine-readable report rather than being left as an undocumented assumption.

`Showcase::TokenBenchmark::Counter` normalizes both sides identically and uses
the pinned `o200k_base` BPE encoding. Every file's content is encoded
independently and the exact counts are summed. Bytes, characters, lines, file
count, tokenizer implementation, tokenizer version, corpus version, and corpus
SHA-256 are also reported.

The only valid static conclusion is:

> Across this fixed corpus and declared scope, one checked-in reference
> contains X fewer `o200k_base` tokens than the other (Y%).

A signed result is retained even when SwiftUI Rails uses more tokens. Report
success means the corpus was valid and countable; it must never mean that a
preferred implementation won. The aggregate reports both a micro result from
summed tokens and a macro mean/median that gives every case equal weight.

The Playground exposes this evidence under **Token benchmark**, and the JSON
contract is available from:

```text
GET /showcase/playground/token-benchmark
```

The same immutable report can be reproduced without a browser from the test
application:

```sh
bin/rails swift_ui:tokens:report
```

## Current parity boundary

Static source review is not executable UI parity. Until both references are
built, mounted, and run through one neutral acceptance suite, the report must
state:

```text
React runtime parity: not run
Provider/model generation: not run
```

An unimplemented API, omitted mount, missing build transform, or uncounted
case-owned controller invalidates that case. A short illustrative DSL excerpt
must never be compared with a complete React feature.

The executable parity gate should cover:

- target lint and build;
- the same DOM and behavior assertions;
- stable collection identity and server round trips;
- keyboard, focus, and accessibility checks;
- XSS, CSRF, and unsafe-URL rejection;
- no console or failed-network errors; and
- mobile, desktop, light, and dark visual states.

All target-owned CSS, JavaScript, component, mount, and configuration source
needed by those checks belongs in the authored production closure.

## Provider output-token layer

Static source tokens show representational compactness. To prove that an LLM
uses fewer output tokens to deliver a passing interface, run a separate paired
provider evaluation.

For every case:

1. Pin the model snapshot, sampling parameters, output cap, language catalogue,
   React scaffold, and response protocol.
2. Start each target in a fresh isolated context with the same neutral brief and
   fixture, followed by a target-specific appendix.
3. Require the same JSON file-bundle response envelope for both targets.
4. Validate every response through the target build and the shared parity gate.
5. Permit at most three diagnostic-driven attempts.
6. Define `tokens_to_green` as the sum of provider-reported output tokens for
   every initial and repair response through the first passing candidate,
   including discarded output and tool-call arguments.
7. Charge failures the fixed output budget and also report `pass_at_budget`;
   never remove failed trials from the denominator.

Run at least 20 paired trials per case, randomize target order, and publish
per-case results plus macro and micro totals, median, interquartile range,
bootstrap confidence interval, first-pass rate, and repair count. Store input,
cached-input, output, and reasoning-token fields separately when the provider
reports them.

The fixed deterministic corpus is therefore a prerequisite and a regression
fixture. It is not a substitute for the provider experiment.

## Separating syntax from framework leverage

A raw React implementation and SwiftUI Rails do not isolate language syntax:
SwiftUI Rails also supplies semantic primitives and behaviors. Mature results
should publish two React tracks rather than blending them:

- a language-isolation track using a frozen React primitive kit with matched
  Stack, Text, Badge, Grid, form, and workflow capabilities; and
- a realistic product track using an explicitly pinned idiomatic React stack.

If SwiftUI Rails wins only against the raw-product track, call the result
framework leverage. If it also wins against matched primitives, the difference
is stronger evidence for DSL syntax and composition efficiency.
