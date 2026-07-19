# Advanced content

SwiftUI Rails provides web-native equivalents for rich SwiftUI content without
claiming platform parity where browser semantics differ.

## AsyncImage

```ruby
async_image(
  "/products/camera.webp",
  alt: "Black rangefinder camera",
  loading_label: "Loading camera…",
  error_label: "Camera image unavailable",
  loading: :lazy,
  fetch_priority: :auto
)
```

`async_image` keeps a normal `img` source. The browser therefore owns HTTP
caching, decoding, lazy loading, preload behavior, and accessibility. Its
declarative phase command only presents `loading`, `success`, and `failure`
states through the gem-owned runtime and correctly recognizes images completed
from cache before runtime connection. Applications do not supply an image
controller or callback.
The only supported cache policy is `:browser`; cache lifetime belongs in HTTP
response headers.

## Sanitized rich text

```ruby
rich_text(article.body)
```

Rich text accepts headings, paragraphs, emphasis, code, quotes, lists, and
links. Scripts, media, forms, embeds, styles, event handlers, arbitrary data
attributes, and unsafe link schemes are removed. Links opening a new browsing
context receive `rel="noopener noreferrer"`.

## WebView

```ruby
web_view(
  "https://www.youtube-nocookie.com/embed/video-id",
  title: "Product tour",
  allow: %i[fullscreen picture-in-picture]
)
```

`web_view` is a sandboxed iframe, not an unrestricted browser. External sources
must appear in the dedicated embed allowlist. Extend that policy during boot:

```ruby
SwiftUIRails::Security::URLValidator.add_approved_embed_domain("media.example.com")
```

Approving a domain for images or links never approves it for frames. No frame
can combine `allow-scripts` and `allow-same-origin`: an external endpoint can
redirect back to the application, where that pair could let framed code remove
its sandbox. External frames default to an opaque origin with scripts and
presentation only; add narrower tokens explicitly when required.

## Charts

```ruby
chart(
  { "Mon" => 18, "Tue" => 31, "Wed" => 27 },
  type: :line,
  title: "Successful deployments",
  description: "Successful deployments by weekday",
  color: :teal
)
```

Bar and line charts are server-rendered SVG with an accessible title and
description. Every exact value is repeated in a visually hidden data table.
They require no JavaScript and support finite numeric values, including
negatives.

## Canvas

```ruby
canvas(
  width: 640,
  height: 360,
  label: "Service health illustration",
  commands: [
    { type: :clear, color: :white },
    { type: :fill_rect, x: 40, y: 80, width: 120, height: 220, color: :blue },
    { type: :text, x: 320, y: 330, text: "API", align: :center }
  ]
)
```

Canvas accepts only `clear`, `fill_rect`, `stroke_rect`, `line`, `circle`, and
`text` commands with bounded numeric geometry and palette/hex colors. It never
evaluates code or accepts arbitrary paths, CSS, fonts, or image URLs. The
canvas includes an accessible label and fallback text.

## Schematic maps

```ruby
map(
  center: [51.5074, -0.1278],
  span: [0.2, 0.4],
  label: "London service points",
  markers: [
    map_marker(latitude: 51.5074, longitude: -0.1278, label: "Westminster")
  ]
)
```

The map is intentionally a `:schematic` coordinate plot. It sends no location
data to a tile provider, shows no roads or terrain, and labels itself as not for
navigation. Markers outside the requested span remain in the accessible exact
coordinate list but are not plotted in the viewport. A real street-map product
should use a separately selected provider SDK with its own privacy, key,
attribution, and accessibility contract.
