# State, binding, and observation

SwiftUI Rails keeps component-local interaction state on the server. The browser receives short-lived capabilities and an opaque encrypted snapshot. Rendered values (a count, an inventory list) still appear in the HTML as presentation data, but the server never accepts client-supplied plaintext as an authoritative props, state, binding, or snapshot input — authority always travels through the signed, encrypted capability.

## State and Binding

```ruby
class QuantityComponent < SwiftUIRails::Component::Base
  prop :label, type: String, default: "Quantity"
  state :count, 0, type: Integer
  binding :step, type: Integer, default: 1

  swift_ui do
    component = @component

    vstack(alignment: :start, spacing: 12) do
      text("#{component.label}: #{component.count}")
        .content_transition(:numeric_text)
        .animation(value: component.count)

      input(type: "number", min: 1, **component.step.input_attributes)

      button("Increase").on_click do
        component.count += component.step.value
      end
    end
  end
end
```

`state` is dynamically typed unless `type:` is supplied. Typed state rejects incompatible restored or assigned values. Mutable defaults are copied per component instance, callable initializers execute only for a genuinely new component, and the encrypted snapshot preserves state across HTTP action and binding updates without rerunning those initializers during restoration.

`binding` exposes a `BindingValue`. Use `input_attributes`, `checkbox_attributes`, or `select_attributes` to produce a normal HTML name/value fallback plus typed reactive metadata. `project` can read and write a nested value on the server, but derived bindings are not transported as independent root bindings.

Rendered action and update requests must present both:

- a short-lived stream token bound to the component DOM identifier; and
- a one-time encrypted snapshot bound to that identifier, component class, issued action descriptors, and the resolved authorization context.

The authorization resolver defaults to the Rails session and `current_user` when they are available. Applications with tenant, account, role, or other authorization boundaries should bind those identities explicitly:

```ruby
config.reactive_authorization_context = lambda do |_subject|
  Current.account&.id
end
```

The configured value is combined with the built-in session/current-user scope, so it only needs to identify the additional tenant, account, role, or policy boundary. Derive it from authenticated server context, never a request parameter. A token rendered for one resolved context is invalid in another. An out-of-band render with no request or configured context cannot infer a user or tenant automatically.

The server restores only declared props, state, and bindings. Props are read-only inputs recovered from the encrypted snapshot; the browser may submit changes only for declared transportable root bindings. Browser-supplied constructor props, undeclared changes, invalid types, forged classes, expired tokens, and mismatched identifiers are rejected or ignored without becoming component inputs. Add every executable component class explicitly to `config.allowed_components` in the initializer.

Reactive snapshot values should be JSON-like scalars and bounded arrays or hashes. Carry a stable scalar identifier such as `product_id`, then reload and authorize the record through a controller, policy, or `observed_resource`. Active Record instances are explicitly rejected because a process-bound model cannot round-trip through a browser-carried snapshot without losing its type, connection, and authorization context.

## Update, retry, and replay contract

Every accepted action or binding update consumes its encrypted snapshot once. A successful render issues a replacement snapshot and renewed stream capability. Reusing the old snapshot returns `409 Conflict`, so one browser response cannot authorize the same server action twice. This gives each issued snapshot an at-most-once mutation boundary; it does not promise that a client which loses the HTTP response can distinguish success from an interrupted request.

The browser client serializes action and binding traffic for a component. Binding changes that arrive while a request is in flight remain queued and are sent only after the response renews the capability. Transient update failures use bounded retry with the pending changes preserved. Expired, invalid, or replayed capabilities dispatch a recoverable browser event and permit at most one guarded page reload to obtain a fresh server render, avoiding a reload loop. Application mutations should still be idempotent where their domain permits it.

Action Cable is notification-only. A subscription is authorized with the same component identity and capability context, but browser messages cannot mutate state or request arbitrary props over the socket. An observed-resource invalidation queues the normal authorized HTTP rerender; Rails remains the state and authorization boundary.

## Observation

Use `observed_resource` for production data whose authority is a database, cache, or service:

```ruby
class InventoryComponent < SwiftUIRails::Component::Base
  observed_resource :inventory, stream: :inventory do
    { available: Inventory.available_count }
  end

  swift_ui do
    text("Available: #{@component.inventory.data.fetch(:available)}")
  end
end
```

After the authoritative transaction commits, broadcast an invalidation marker:

```ruby
SwiftUIRails::Reactive::ObservableStore.invalidate(:inventory)
```

Authorized browsers receive only the stream name and an opaque revision over the read-only subscription. They request a fresh render through the normal one-time HTTP capability, and the component loader reads committed data again. Observed values are not placed in Action Cable messages, component capabilities, or hidden DOM attributes.

The resource loader executes once for each component render. Every read during that render uses a defensive copy of the same authoritative snapshot, so a fingerprint, the view body, and reactive metadata cannot observe different revisions mid-render.

`observed_object` and `ObservableStore` remain useful for thread-safe, in-process coordination. Their render-time subscriptions are always released so request-scoped components are not retained. They do not replace a durable database, distributed cache, authorization policy, or transaction boundary.

`ObservableStore#update` is atomic: if the mutation block raises, the prior data is restored and no local notification or Action Cable invalidation is emitted. Browser subscriptions use the store object's normalized `id`, including stores returned dynamically by a callable, rather than assuming the observed property name is the stream name.

## Browser ownership

The browser still owns live focus, native form editing, HTTP caching, DOM lifecycle, and accessibility state. The gem-owned DOM runtime carries declared changes back to Rails; it is a protocol interpreter, not an independent client-side model store or application programming surface. Critical persistence belongs in explicit Rails mutations, not `on_disappear` or transient browser events.
