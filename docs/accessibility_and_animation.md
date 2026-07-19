# Accessibility and value-driven animation

SwiftUI Rails exposes accessibility intent as semantic HTML and ARIA. The browser accessibility tree remains authoritative; these modifiers do not emulate Apple's accessibility runtime.

```ruby
text("42")
  .accessibility_identifier("current-reading")
  .accessibility_label("Current reading")
  .accessibility_value("42 volts")
  .accessibility_hint("Updated every minute")
  .accessibility_role(:status)
  .accessibility_live(:polite, atomic: true)
  .accessibility_state(busy: false, current: :step)
```

Prefer native elements such as `button`, `a`, `input`, `progress`, and `meter`. Use `.accessibility_role` or `.accessibility_traits` only when the native element cannot express the intended behavior. Available modifiers are:

- `.accessibility_label`, `.accessibility_value`, and `.accessibility_hint`
- `.accessibility_role` and `.accessibility_traits`
- `.accessibility_hidden` and `.accessibility_live`
- `.accessibility_heading` and `.accessibility_identifier`
- `.accessibility_state` for selected, expanded, pressed, busy, checked, and current state

Values are bounded and allowlisted before rendering. These APIs intentionally do not claim parity with native accessibility actions, custom rotors, or Apple platform assistive-technology APIs.

## Animation

CSS transitions are the web animation authority. The `value:` argument records the state value associated with a render, while Turbo or browser DOM changes provide the transition lifecycle.

```ruby
text(total.to_s)
  .animation(
    :ease_in_out,
    duration: 0.25,
    value: total,
    properties: :colors
  )
  .content_transition(:numeric_text)
```

Curves are `:linear`, `:ease_in`, `:ease_out`, `:ease_in_out`, and `:spring`. Properties are `:all`, `:opacity`, `:transform`, `:colors`, and `:shadow`. Content transitions are `:identity`, `:opacity`, `:numeric_text`, and `:interpolate`.

Generated CSS disables `.swift-ui-value-animation` transitions when the user requests reduced motion. This is a value-associated CSS transition contract, not SwiftUI transaction or insertion/removal transition parity.
