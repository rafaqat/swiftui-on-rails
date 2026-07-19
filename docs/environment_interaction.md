# Environment, focus, lifecycle, and interactions

These APIs preserve portable SwiftUI intent while keeping Rails and browser ownership explicit. They are not wrappers around an Apple runtime.

## Environment

Declare the values a component reads:

```ruby
class PriceComponent < SwiftUIRails::Component::Base
  environment :currency, default: "GBP", type: String
  environment :account, required: true

  swift_ui do
    text("#{currency} for #{account.name}")
  end
end
```

An ancestor can override values for one component or one render subtree:

```ruby
render PriceComponent.new.with_environment(currency: "EUR", account: current_account)

environment_scope(currency: "USD", account: current_account) do
  render PriceComponent.new
end
```

Environment contexts are immutable boundaries stored in Ruby's fiber-local `Thread#[]` storage, so nested renders inherit them without crossing concurrent request or fiber boundaries even when Rails keeps its default thread isolation setting. Values are never serialized into HTML. Do not use the environment as an authorization decision by itself; authorization must still be enforced by Rails controllers, policies, and models.

For direct reactive component endpoints, install request middleware or an `around_action` that derives required values again (for example from `Current.account`). An element-local environment override exists only while that ancestor subtree renders; private values are intentionally not copied into browser-owned reactive snapshots.

Built-in defaults are available for `locale`, `time_zone`, `color_scheme`, `layout_direction`, and `reduced_motion`. Applications may declare their own lower-case underscore keys.

## FocusState

`focus_state` stores the focus requested for the next server render. The browser's `document.activeElement` remains authoritative while the page is live.

```ruby
class LoginComponent < SwiftUIRails::Component::Base
  focus_state :focused_field, values: %i[email password]

  swift_ui do
    focus_scope(:login) do
      textfield(placeholder: "Email")
        .focused(:focused_field, equals: :email)

      textfield(placeholder: "Password")
        .focused(focused_field_focus_binding, equals: :password)
    end
  end
end
```

Setting `self.focused_field = :password` in a server action requests password focus after that component is replaced. Native `focus` and `blur` produce bubbling `swift-ui-focus-change` events. They intentionally do not post every focus transition to the server.

Use `.focusable` to opt a custom element into the tab order. Prefer native controls and links whenever they fit.

## Lifecycle and tasks

DOM connection is the portable web lifecycle:

```ruby
lifecycle_scope(id: "profile") do
  text("Server-rendered fallback")
end
  .on_appear { load_started }
  .on_disappear { record_best_effort_departure }
  .task(url: "/profile/summary", method: :get)
```

The gem-owned lifecycle command emits `swift-ui-appear` and `swift-ui-disappear`. Applications declare the lifecycle intent in Ruby; they do not attach JavaScript callbacks. Disappear is best effort and must not be used for critical persistence because browsers can terminate a page without running cleanup.

`.task` accepts only an absolute same-origin path and `GET` or `POST`. It starts on connect by default, exposes `loading`, `success`, and `failure` through `data-swift-ui-task-state` and bubbling events, and aborts its fetch when the element disconnects. Automatic tasks are GET-only; POST requires `trigger: :manual`, and `.refreshable` supplies that safer manual contract. The initial child content remains the no-JavaScript fallback. Aborting a browser fetch stops client work but does not guarantee that a Rails server process or background job stops after it has begun.

The default task response mode is `:event`. `response: :replace_content` may insert HTML returned by the same Rails origin and should only target an endpoint whose complete response is trusted.

## Gestures and keyboard input

```ruby
button("Save").on_tap { save }

div("Hold for options")
  .on_long_press(minimum_duration: 0.5) { open_options }

div("Move")
  .on_drag(axis: :horizontal, keyboard_step: 10) { |event| persist_move(event) }

div("Search shortcut")
  .on_key_press(keys: :k, modifiers: %i[control]) { focus_search }
```

Tap makes non-native targets keyboard-operable with Enter and Space, though a real `button` is preferred. Long press supports pointer and keyboard hold. Drag emits `swift-ui-drag-start`, `swift-ui-drag-change`, and `swift-ui-drag-end`; only the end event invokes its optional Ruby action. Generic pointer drag has no automatic keyboard meaning, so arrow-key drag is enabled only when `keyboard_step` is supplied.

Gesture values are bounded and action events are allowlisted before they enter RenderIR. Multiple actions on one element use an explicit semantic event-to-action map instead of controller strings or depending on DOM attribute order. The framework runtime recognizes only those declared gestures. Long press should enhance a visible button or menu rather than hide a critical action that users cannot discover.
