import { createConsumer } from "@rails/actioncable"
import {
  RENDER_PATCH_VERSION,
  applyRenderPatch,
  isRenderPatchError
} from "swift_ui_render_patch"

const TRANSIENT_RESPONSE_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504])
const CAPABILITY_RESPONSE_STATUSES = new Set([401, 403, 409, 419])
const MAX_UPDATE_RETRIES = 4
const CAPABILITY_RELOAD_GUARD_MS = 5 * 60 * 1000

// Action Cable multiplexes subscriptions over one socket. Keep that property
// across every reactive component on the page and only close the socket after
// the final component disconnects.
const sharedCable = {
  consumer: null,
  references: 0,

  acquire() {
    if (!this.consumer) this.consumer = createConsumer()
    this.references += 1
    return this.consumer
  },

  release() {
    this.references = Math.max(0, this.references - 1)
    if (this.references === 0 && this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
  }
}
const MAX_EVENT_DETAIL_DEPTH = 4
const MAX_EVENT_DETAIL_ENTRIES = 64
const MAX_EVENT_DETAIL_KEY_LENGTH = 128
const MAX_EVENT_DETAIL_STRING_LENGTH = 2048
const MAX_EVENT_DETAIL_BYTES = 16 * 1024
const MAX_ACTION_PAYLOAD_BYTES = 64 * 1024
const EXIT_TRANSITION_FALLBACK_MS = 450
const DELEGATED_ACTION_EVENTS = Object.freeze([
  'click', 'dblclick',
  'mousedown', 'mouseup', 'mouseover', 'mouseout', 'mousemove',
  'pointerdown', 'pointerup', 'pointermove', 'pointercancel',
  'keydown', 'keyup', 'submit', 'change', 'input', 'focusin', 'focusout',
  'load', 'error', 'dragstart', 'dragover', 'drop', 'dragend', 'toggle', 'cancel', 'close',
  'swift-ui-appear', 'swift-ui-disappear', 'swift-ui-long-press',
  'swift-ui-drag-end', 'swift-ui-key-press'
])
const DELEGATED_ACTION_EVENT_SET = new Set(DELEGATED_ACTION_EVENTS)

function byteLength(value) {
  return new TextEncoder().encode(value).byteLength
}

function sanitizeEventDetail(detail) {
  const seen = new WeakSet()
  const budget = { entries: MAX_EVENT_DETAIL_ENTRIES }

  const visit = (value, depth, arrayMember = false) => {
    if (value === null || typeof value === 'boolean') return value
    if (typeof value === 'string') return value.slice(0, MAX_EVENT_DETAIL_STRING_LENGTH)
    if (typeof value === 'number') return Number.isFinite(value) ? value : (arrayMember ? null : undefined)
    if (typeof value !== 'object' || depth > MAX_EVENT_DETAIL_DEPTH || budget.entries <= 0) {
      return arrayMember ? null : undefined
    }

    const isArray = Array.isArray(value)
    const isPlainObject = Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null
    if (!isArray && !isPlainObject) return arrayMember ? null : undefined
    if (seen.has(value)) return arrayMember ? null : undefined
    seen.add(value)

    if (isArray) {
      const result = []
      for (const item of value) {
        if (budget.entries <= 0) break
        budget.entries -= 1
        result.push(visit(item, depth + 1, true))
      }
      return result
    }

    const result = Object.create(null)
    for (const [key, item] of Object.entries(value)) {
      if (budget.entries <= 0) break
      if (key.length > MAX_EVENT_DETAIL_KEY_LENGTH || ['__proto__', 'constructor', 'prototype'].includes(key)) continue

      budget.entries -= 1
      const sanitized = visit(item, depth + 1)
      if (sanitized !== undefined) result[key] = sanitized
    }
    return result
  }

  try {
    const sanitized = visit(detail, 0)
    if (sanitized === undefined) return undefined

    const normalized = Array.isArray(sanitized) || sanitized === null || typeof sanitized !== 'object'
      ? { value: sanitized }
      : sanitized
    return byteLength(JSON.stringify(normalized)) <= MAX_EVENT_DETAIL_BYTES ? normalized : undefined
  } catch (_serializationError) {
    return undefined
  }
}

// Delegated, server-authoritative action transport. It contains no application
// behavior; opaque action ids are interpreted only by the Rails component.
class SwiftUIActionTransport {
  constructor(runtime) {
    this.runtime = runtime
  }

  handleAction(event, target) {
    // Get the action ID from the event target
    const actionId = this.findActionId(target, event.type)

    if (!actionId) {
      console.warn("No action ID found for event", event)
      return
    }

    // Find component metadata by traversing up the DOM tree
    const componentData = this.findComponentData(target)

    if (!componentData.component_id || !componentData.component_class) {
      console.error("Could not find component metadata", componentData)
      return
    }

    // Prepare the action data
    const reactiveRoot = this.reactiveRoot(target)
    const storyContext = target.closest('[data-sui-story-session]')
    const snapshotToken = this.findReactiveValue('snapshot-token', reactiveRoot)
    const streamToken = this.findReactiveValue('stream-token', reactiveRoot)
    const actionData = {
      action_id: actionId,
      component_id: componentData.component_id,
      component_class: componentData.component_class,
      event_type: event.type,
      target_value: this.getTargetValue(target),
      target_checked: target.checked,
      target_dataset: Object.fromEntries(Object.entries(target.dataset)),
      snapshot_token: snapshotToken,
      stream_token: streamToken,
      render_patch_version: RENDER_PATCH_VERSION,
      // Optional semantic Storybook context; never sourced from mutable globals.
      story_session_id: storyContext?.dataset.suiStorySession,
      story_name: storyContext?.dataset.suiStory,
      story_variant: storyContext?.dataset.suiStoryVariant
    }
    const hasReactiveCapability = Boolean(snapshotToken && streamToken)
    const hasStoryCapability = Boolean(
      storyContext?.dataset.suiStorySession && storyContext?.dataset.suiStory
    )
    if (!hasReactiveCapability && !hasStoryCapability) return false

    const eventDetail = sanitizeEventDetail(event.detail)
    if (eventDetail !== undefined) actionData.event_detail = eventDetail

    this.preventConflictingNativeDefault(event, target)

    // Send action to server
    this.enqueueAction(actionData, reactiveRoot, target)
    return true
  }

  preventConflictingNativeDefault(event, target) {
    if (!event?.cancelable || typeof event.preventDefault !== 'function') return

    const submits = event.type === 'submit'
    const nativeControl = target.closest?.(
      'a[href], area[href], button[type="submit"], input[type="submit"], input[type="image"]'
    )
    const navigatesOrSubmits = event.type === 'click' && Boolean(nativeControl)
    if (submits || navigatesOrSubmits) event.preventDefault()
  }

  findReactiveValue(name, root = this.reactiveRoot()) {
    const canonicalName = name === 'snapshot-token' ? 'suiSnapshot' : 'suiStream'
    return root?.dataset[canonicalName] ||
      root?.getAttribute(`data-swift-ui-reactive-${name}-value`) || null
  }

  findComponentData(element) {
    const root = this.reactiveRoot(element)
    if (root) return {
      component_id: root.dataset.suiId ||
        root.getAttribute('data-swift-ui-reactive-component-id-value') || root.id || '',
      component_class: root.dataset.suiComponent ||
        root.getAttribute('data-swift-ui-reactive-component-class-value') || ''
    }

    // Fallback to element ID if nothing found
    return {
      component_id: element?.id || '',
      component_class: ''
    }
  }

  findActionId(element, eventType) {
    // Newer DSL renders carry an explicit event-to-action map. This matters
    // when one accessible element supports more than one interaction (for
    // example tap plus long press); DOM attribute order is not action routing.
    const actionMap = element.dataset.suiActions || element.dataset.swiftUiComponentActionMapValue
    if (actionMap) {
      try {
        const mappedAction = JSON.parse(actionMap)[eventType]
        if (mappedAction) return mappedAction
      } catch (error) {
        console.error("Invalid SwiftUI action map", error)
        return null
      }
    }

    // Backwards compatibility for markup rendered before action maps existed.
    // Look for data-swift-ui-component-action-* attributes
    const attributes = element.attributes
    for (let i = 0; i < attributes.length; i++) {
      const attr = attributes[i]
      if (attr.name.startsWith('data-swift-ui-component-action-')) {
        return attr.value
      }
    }
    return null
  }

  getTargetValue(target) {
    // Handle different input types
    if (target.tagName === 'SELECT') {
      return target.value
    } else if (target.type === 'checkbox' || target.type === 'radio') {
      return target.checked
    } else if (target.value !== undefined) {
      return target.value
    } else {
      return target.textContent
    }
  }

  reactiveRoot(element = null) {
    return element?.closest?.('[data-sui-root="1"], [data-swift-ui-reactive="true"]') || null
  }

  reactiveController(root) {
    if (!root) return null
    return this.runtime.transportFor(root)
  }

  enqueueAction(actionData, reactiveRoot = this.reactiveRoot(), focusTarget = null) {
    const queueOwner = reactiveRoot || document
    const previousAction = queueOwner._swiftUIActionQueue || Promise.resolve()
    const queuedAction = previousAction
      .catch(() => {})
      .then(() => this.sendAction(actionData, reactiveRoot, focusTarget))

    queueOwner._swiftUIActionQueue = queuedAction
    queuedAction.finally(() => {
      if (queueOwner._swiftUIActionQueue === queuedAction) {
        delete queueOwner._swiftUIActionQueue
      }
    }).catch(() => {})
    return queuedAction
  }

  async sendAction(actionData, reactiveRoot = this.reactiveRoot(), focusTarget = null) {
    const url = '/swift_ui/actions'
    const reactiveController = this.reactiveController(reactiveRoot)
    let externalUpdateStarted = false
    let capabilitiesRemainValid = true

    try {
      // Flush debounced bindings first, then read the renewed capabilities at
      // the moment this queued action actually starts.
      if (reactiveController) {
        const ready = await reactiveController.flushPendingUpdates()
        if (!ready) {
          this.dispatch('action-error', {
            detail: { reason: 'reactive-update-pending', action: actionData },
            target: reactiveRoot || document
          })
          return
        }
        reactiveController.beginExternalUpdate()
        externalUpdateStarted = true
      }

      actionData.snapshot_token = this.findReactiveValue('snapshot-token', reactiveRoot)
      actionData.stream_token = this.findReactiveValue('stream-token', reactiveRoot)
      actionData.render_patch_version = RENDER_PATCH_VERSION
      const requestBody = JSON.stringify(actionData)
      if (byteLength(requestBody) > MAX_ACTION_PAYLOAD_BYTES) {
        throw new RangeError('SwiftUI action payload exceeds the client limit')
      }

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: requestBody
      })

      const contentType = response.headers.get('content-type') || ''
      const payload = contentType.includes('json')
        ? await response.json().catch(() => ({}))
        : await response.text()

      if (!response.ok) {
        if (this.isCapabilityResponse(response.status, payload)) {
          capabilitiesRemainValid = false
          this.handleInvalidCapability(response.status, payload, reactiveController, reactiveRoot)
        }
        throw new Error(`Action failed with HTTP ${response.status}`)
      }

      if (contentType.includes('turbo-stream')) {
        if (window.Turbo) window.Turbo.renderStreamMessage(payload)
      } else if (payload && typeof payload === 'object') {
        this.applyActionResponse(payload, reactiveController, reactiveRoot, focusTarget)
      }
    } catch (error) {
      console.error('Error sending action:', error)
      this.dispatch('action-error', {
        detail: { error, action: actionData },
        target: reactiveRoot || document
      })
    } finally {
      if (externalUpdateStarted) reactiveController.endExternalUpdate(capabilitiesRemainValid)
    }
  }

  applyActionResponse(data, reactiveController = this.reactiveController(), reactiveRoot = this.reactiveRoot(), focusTarget = null) {
    if (reactiveController) {
      reactiveController.applyRenderResponse(data, focusTarget)
    } else if (data.patch && reactiveRoot) {
      try {
        applyRenderPatch(reactiveRoot, data.patch, { focusTarget })
      } catch (error) {
        if (isRenderPatchError(error)) this.handleRenderPatchFailure(error, reactiveRoot)
        throw error
      }
    } else if (data.html) {
      const template = document.createElement('template')
      template.innerHTML = data.html.trim()
      const renderedRoot = template.content.querySelector('[data-sui-root="1"], [data-swift-ui-reactive="true"]')
      if (reactiveRoot && renderedRoot) {
        renderedRoot.dataset.swiftUiRenderMode = "html"
        reactiveRoot.replaceWith(renderedRoot)
      }
    }

    if (data.redirect_to && window.Turbo) {
      window.Turbo.visit(data.redirect_to)
    } else if (data.redirect_to) {
      window.location.assign(data.redirect_to)
    } else if (data.update_component) {
      this.dispatch('update', { detail: data, target: reactiveRoot || document })
    }
  }

  handleRenderPatchFailure(error, root) {
    const event = this.dispatch('patch-error', {
      detail: {
        code: error.code,
        message: error.message,
        operationIndex: error.operationIndex,
        componentId: root?.dataset.suiId || root?.id || ''
      },
      bubbles: true,
      cancelable: true,
      target: root || document
    })
    if (!error.defaultPrevented && !event.defaultPrevented) this.reloadAfterRenderPatchError()
  }

  reloadAfterRenderPatchError() {
    window.location.reload()
  }

  isCapabilityResponse(status, payload) {
    if ([401, 403, 409, 419].includes(status)) return true
    const message = typeof payload === 'object' ? payload?.error : payload
    return status === 422 && /authoriz|capabil|snapshot|expired|token/i.test(message || '')
  }

  handleInvalidCapability(status, payload, reactiveController, reactiveRoot) {
    if (reactiveController) {
      reactiveController.recoverInvalidCapability({ status, payload })
      return
    }

    this.dispatch('capability-error', {
      detail: { status, error: payload },
      bubbles: true,
      target: reactiveRoot || document
    })
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  // Allow programmatic triggering of actions
  dispatch(name, options = {}) {
    const element = options.target || document
    const event = new CustomEvent(`swift-ui-component:${name}`, {
      bubbles: options.bubbles !== false,
      cancelable: options.cancelable === true,
      detail: options.detail || {}
    })
    element.dispatchEvent(event)
    return event
  }

  triggerAction(actionId, data = {}, element = null) {
    const target = element || document.querySelector(`[data-sui-actions*='${CSS.escape(actionId)}']`)
    const componentData = this.findComponentData(target)
    const reactiveRoot = this.reactiveRoot(target)
    const actionData = {
      action_id: actionId,
      component_id: componentData.component_id,
      component_class: componentData.component_class,
      event_type: 'programmatic',
      snapshot_token: this.findReactiveValue('snapshot-token', reactiveRoot),
      stream_token: this.findReactiveValue('stream-token', reactiveRoot),
      ...data,
      render_patch_version: RENDER_PATCH_VERSION
    }

    return this.enqueueAction(actionData, reactiveRoot)
  }
}

class ReactiveResponseError extends Error {
  constructor(response, payload) {
    super(`Reactive update failed with HTTP ${response.status}`)
    this.name = "ReactiveResponseError"
    this.status = response.status
    this.payload = payload
  }
}

// Server-authoritative component state transport. This is a plain browser
// object owned by SwiftUIRuntime, not an application controller or state store.
class SwiftUIReactiveTransport {
  constructor(element, runtime) {
    this.element = element
    this.runtime = runtime
  }

  get componentIdValue() {
    return this.element.dataset.suiId ||
      this.element.getAttribute('data-swift-ui-reactive-component-id-value') ||
      this.element.id || ''
  }

  get componentClassValue() {
    return this.element.dataset.suiComponent ||
      this.element.getAttribute('data-swift-ui-reactive-component-class-value') || ''
  }

  get streamTokenValue() {
    return this.element.dataset.suiStream ||
      this.element.getAttribute('data-swift-ui-reactive-stream-token-value') || ''
  }

  set streamTokenValue(value) {
    this.element.dataset.suiStream = value
    if (this.element.hasAttribute('data-swift-ui-reactive-stream-token-value')) {
      this.element.setAttribute('data-swift-ui-reactive-stream-token-value', value)
    }
  }

  get snapshotTokenValue() {
    return this.element.dataset.suiSnapshot ||
      this.element.getAttribute('data-swift-ui-reactive-snapshot-token-value') || ''
  }

  set snapshotTokenValue(value) {
    this.element.dataset.suiSnapshot = value
    if (this.element.hasAttribute('data-swift-ui-reactive-snapshot-token-value')) {
      this.element.setAttribute('data-swift-ui-reactive-snapshot-token-value', value)
    }
  }

  get updateUrlValue() {
    return this.element.dataset.suiUpdateUrl ||
      this.element.getAttribute('data-swift-ui-reactive-update-url-value') ||
      '/swift_ui/components/update'
  }

  get debounceValue() {
    const raw = this.element.dataset.suiDebounce ||
      this.element.getAttribute('data-swift-ui-reactive-debounce-value')
    const value = Number(raw)
    return Number.isFinite(value) && value >= 0 ? value : 100
  }

  connect() {
    this.connectionGeneration = (this.connectionGeneration || 0) + 1
    this.connected = true
    this.updateTimer = null
    this.retryTimer = null
    this.currentUpdate = null
    this.updateAbortController = null
    this.pendingChanges = this.pendingChanges || {}
    this.updateInFlight = false
    this.externalUpdates = 0
    this.updateRetryCount = 0
    this.idleWaiters = []
    this.capabilityRecoveryStarted = false
    this.setupStateTracking()
    this.setupObservers()
    this.subscribeToUpdates()

    // Register globally for coordination
    this.registerComponent()
  }

  disconnect() {
    this.connectionGeneration = (this.connectionGeneration || 0) + 1
    this.connected = false
    clearTimeout(this.updateTimer)
    clearTimeout(this.retryTimer)
    this.updateTimer = null
    this.retryTimer = null
    this.updateAbortController?.abort()
    this.updateAbortController = null
    this.updateInFlight = false
    this.externalUpdates = 0
    this.currentUpdate = null
    this.resolveIdleWaiters(false)

    // Clean up observers
    if (this.stateObserver) {
      this.stateObserver.disconnect()
    }

    this.unsubscribeFromUpdates()
    this.unregisterComponent()
  }

  setupStateTracking() {
    // Track state changes via MutationObserver
    this.stateObserver = new MutationObserver((mutations) => {
      this.handleStateMutations(mutations)
    })

    this.stateObserver.observe(this.element, {
      attributes: true,
      attributeFilter: ['data-state-changes', 'data-binding-changes', 'data-observed-changes'],
      subtree: true
    })
  }

  setupObservers() {
    this.storeSubscriptions = {}
    const observedStores = this.element.dataset.suiObservedStores || this.element.dataset.observedStores
    if (observedStores) {
      try {
        JSON.parse(observedStores).forEach(storeName => this.observeStore(storeName))
      } catch (error) {
        this.handleUpdateError(error)
      }
    }
  }

  handleStateMutations(mutations) {
    const changes = {}

    mutations.forEach(mutation => {
      const target = mutation.target

      // Parse state changes
      if (mutation.attributeName === 'data-state-changes') {
        const stateChanges = JSON.parse(target.dataset.stateChanges || '[]')
        stateChanges.forEach(change => {
          changes[`state.${change.name}`] = change
        })
      }

      // Parse binding changes
      if (mutation.attributeName === 'data-binding-changes') {
        const bindingChanges = JSON.parse(target.dataset.bindingChanges || '[]')
        bindingChanges.forEach(change => {
          changes[`binding.${change.name}`] = change
        })
      }

      // Parse observed object changes
      if (mutation.attributeName === 'data-observed-changes') {
        const observedChanges = JSON.parse(target.dataset.observedChanges || '{}')
        Object.entries(observedChanges).forEach(([store, storeChanges]) => {
          Object.entries(storeChanges).forEach(([key, change]) => {
            changes[`observed.${store}.${key}`] = change
          })
        })
      }
    })

    if (Object.keys(changes).length > 0) {
      this.scheduleUpdate(changes)
    }
  }

  updateBinding(name, value) {
    // Update binding value
    const bindingData = {
      name: name,
      value: value,
      timestamp: Date.now()
    }

    // Dispatch custom event for other components
    this.dispatch('binding-change', {
      detail: bindingData,
      bubbles: true
    })

    // Schedule component update
    this.scheduleUpdate({ [`binding.${name}`]: { new: value } })
  }

  observeStore(storeName) {
    // Subscribe to store changes via ActionCable
    if (!this.storeSubscriptions) {
      this.storeSubscriptions = {}
    }

    this.storeSubscriptions[storeName] = true
  }

  scheduleUpdate(changes) {
    this.mergePendingChanges(changes)

    if (!this.updateInFlight && !this.retryTimer && this.updateRetryCount >= MAX_UPDATE_RETRIES) {
      this.updateRetryCount = 0
    }

    // A request (including a server action) owns the current capability until
    // its response renews it. Later input stays queued and cannot race ahead
    // with the old snapshot.
    if (this.updateInFlight || this.externalUpdates > 0 || this.retryTimer) return

    clearTimeout(this.updateTimer)
    this.updateTimer = setTimeout(() => this.performUpdate(), this.debounceValue)
  }

  async performUpdate() {
    if (!this.connected || this.updateInFlight || this.externalUpdates > 0) return this.currentUpdate

    clearTimeout(this.updateTimer)
    this.updateTimer = null

    const changes = this.pendingChanges || {}
    this.pendingChanges = {}

    if (Object.keys(changes).length === 0) return

    this.updateInFlight = true
    this.updateAbortController = new AbortController()
    const connectionGeneration = this.connectionGeneration
    let retryDelay = null
    let shouldRunQueuedChanges = false

    this.currentUpdate = (async () => {
      // Prepare update data
      const updateData = {
        component_id: this.componentIdValue,
        component_class: this.componentClassValue,
        stream_token: this.streamTokenValue,
        snapshot_token: this.snapshotTokenValue,
        render_patch_version: RENDER_PATCH_VERSION,
        changes: changes
      }

      // Perform update via fetch or Turbo
      const response = await fetch(this.updateUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify(updateData),
        signal: this.updateAbortController.signal
      })

      const contentType = response.headers.get('content-type') || ''
      let payload
      if (contentType.includes('json')) {
        payload = await response.json().catch(() => ({}))
      } else {
        payload = await response.text()
      }

      if (!response.ok) throw new ReactiveResponseError(response, payload)

      if (contentType.includes('turbo-stream')) {
        if (window.Turbo) window.Turbo.renderStreamMessage(payload)
      } else if (payload && typeof payload === 'object') {
        this.applyRenderResponse(payload)
      }

      this.updateRetryCount = 0
      this.clearCapabilityReloadGuard()
      shouldRunQueuedChanges = true
    })().catch((error) => {
      if (connectionGeneration !== this.connectionGeneration) return
      if (!this.connected && error.name === 'AbortError') return

      // A patch response already committed the server mutation and renewed its
      // one-time capability. Retrying that mutation could apply it twice. Other
      // failures retain the batch, while newer input still wins on merge.
      if (!isRenderPatchError(error)) {
        this.mergePendingChanges(changes, { preserveNewer: true })
      }

      if (isRenderPatchError(error)) {
        // The patch failure handler already selected reload or a canceled
        // recovery. The common error boundary below reports it exactly once.
      } else if (this.isCapabilityError(error)) {
        this.recoverInvalidCapability(error)
      } else if (this.isTransientError(error) && this.updateRetryCount < MAX_UPDATE_RETRIES) {
        this.updateRetryCount += 1
        retryDelay = Math.min(250 * (2 ** (this.updateRetryCount - 1)), 2000)
      }

      console.error('Failed to update component:', error)
      this.handleUpdateError(error)
    }).finally(() => {
      if (connectionGeneration !== this.connectionGeneration) return

      this.updateInFlight = false
      this.updateAbortController = null
      this.currentUpdate = null

      if (!this.connected) return

      if (retryDelay !== null) {
        this.retryTimer = setTimeout(() => {
          this.retryTimer = null
          this.performUpdate()
        }, retryDelay)
      } else if (shouldRunQueuedChanges && this.hasPendingChanges()) {
        // The previous response has renewed snapshotTokenValue before this
        // follow-up is allowed to begin.
        this.updateTimer = setTimeout(() => this.performUpdate(), 0)
      } else if (!this.hasPendingChanges()) {
        this.resolveIdleWaiters(true)
      } else {
        // A permanent or exhausted failure retains pendingChanges, but callers
        // waiting to perform an action must not continue with a stale token.
        this.resolveIdleWaiters(false)
      }
    })

    return this.currentUpdate
  }

  updateComponent(html, focusTarget = null) {
    if (typeof html !== 'string') return

    // Full HTML is the deterministic fallback for a server that cannot produce
    // a bounded patch. Keyed responses bypass this whole-root replacement.
    const template = document.createElement('template')
    template.innerHTML = html.trim()
    const renderedRoot = template.content.querySelector('[data-sui-root="1"], [data-swift-ui-reactive="true"]')
    const requestedFocusTarget = focusTarget instanceof HTMLElement && this.element.contains(focusTarget) ?
      focusTarget : null
    const activeElement = requestedFocusTarget ||
      (document.activeElement instanceof HTMLElement && this.element.contains(document.activeElement) ?
        document.activeElement : null)
    const restoreActiveControl = activeElement && !this.isEditableControl(activeElement)
    const activeControlId = restoreActiveControl ? activeElement.id : null

    // A successful render renews the encrypted server snapshot. The root DOM
    // node remains stable for focus and controller continuity, so copy renewed
    // root-level lifecycle values explicitly before morphing its children.
    if (renderedRoot) {
      const renewedSnapshot = renderedRoot.dataset.suiSnapshot ||
        renderedRoot.getAttribute('data-swift-ui-reactive-snapshot-token-value')
      const renewedStreamToken = renderedRoot.dataset.suiStream ||
        renderedRoot.getAttribute('data-swift-ui-reactive-stream-token-value')
      this.applyRenewedCapabilities({
        snapshot_token: renewedSnapshot,
        stream_token: renewedStreamToken
      })
    }

    // The server renders a complete component root. Morph only its children so
    // the transport object, capability token, and focus remain stable.
    if (window.morphdom && renderedRoot) {
      morphdom(this.element, renderedRoot, {
        childrenOnly: true,
        onBeforeElUpdated: (fromEl, toEl) => {
          // Protect in-progress user input, but let focused buttons and other
          // non-editable controls receive renewed labels and ARIA state. With
          // stable ids morphdom updates those controls in place, preserving
          // focus without leaving their server-rendered state stale.
          if (fromEl === document.activeElement && this.isEditableControl(fromEl)) {
            return false
          }
          if (restoreActiveControl && fromEl === activeElement) {
            toEl.dataset.swiftUiFocusRestore = "true"
          }
          return true
        }
      })
    } else {
      this.element.innerHTML = renderedRoot ? renderedRoot.innerHTML : html
    }

    this.element.dataset.swiftUiRenderMode = "html"
    delete this.element.dataset.swiftUiPatchOperations

    if (restoreActiveControl) {
      const restoreControlFocus = () => {
        const markedTarget = this.element.querySelector('[data-swift-ui-focus-restore="true"]')
        const identifiedTarget = activeControlId ? document.getElementById(activeControlId) : null
        const currentFocusTarget = markedTarget ||
          (identifiedTarget && this.element.contains(identifiedTarget) ? identifiedTarget : null) ||
          (activeElement.isConnected ? activeElement : null)
        markedTarget?.removeAttribute("data-swift-ui-focus-restore")
        if (currentFocusTarget instanceof HTMLElement) {
          try {
            currentFocusTarget.focus({ preventScroll: true })
          } catch (_error) {
            currentFocusTarget.focus()
          }
        }
      }
      restoreControlFocus()
    }

    this.setupObservers()
  }

  isEditableControl(element) {
    if (!(element instanceof HTMLElement)) return false
    if (element.isContentEditable) return true
    if (element.matches("textarea, select")) return true
    if (!(element instanceof HTMLInputElement)) return false

    return !["button", "submit", "reset", "checkbox", "radio", "range", "color", "file", "hidden"]
      .includes(element.type)
  }

  applyRenderResponse(data, focusTarget = null) {
    // Capabilities are renewed even if client-side patch validation fails. A
    // malformed patch must never cause the already-committed server action to
    // be retried with its consumed snapshot.
    this.applyRenewedCapabilities(data)

    if (data.patch) {
      try {
        const result = applyRenderPatch(this.element, data.patch, {
          focusTarget,
          preserveBindingNames: this.pendingBindingNames()
        })
        this.setupObservers()
        return result
      } catch (error) {
        if (isRenderPatchError(error)) this.handleRenderPatchFailure(error)
        throw error
      }
    }

    if (data.html) this.updateComponent(data.html, focusTarget)
    return null
  }

  pendingBindingNames() {
    return Object.keys(this.pendingChanges || {}).flatMap((key) => {
      return key.startsWith("binding.") ? [key.slice("binding.".length)] : []
    })
  }

  handleRenderPatchFailure(error) {
    const event = this.dispatch('patch-error', {
      detail: {
        code: error.code,
        message: error.message,
        operationIndex: error.operationIndex,
        componentId: this.componentIdValue
      },
      bubbles: true,
      cancelable: true
    })
    if (!error.defaultPrevented && !event.defaultPrevented) this.reloadAfterRenderPatchError()
  }

  reloadAfterRenderPatchError() {
    window.location.reload()
  }

  subscribeToUpdates() {
    // Subscribe to ActionCable for real-time updates
    if (!this.cableLease) {
      this.consumer = sharedCable.acquire()
      this.cableLease = true
    }

    if (this.channel) this.channel.unsubscribe()
    this.channel = this.consumer.subscriptions.create(
      {
        channel: "SwiftUIRails::Reactive::ReactiveChannel",
        component_id: this.componentIdValue,
        component_class: this.componentClassValue,
        stream_token: this.streamTokenValue,
        snapshot_token: this.snapshotTokenValue
      },
      {
        received: (data) => {
          this.handleChannelUpdate(data)
        }
      }
    )
  }

  unsubscribeFromUpdates({ releaseConsumer = true } = {}) {
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }
    if (releaseConsumer && this.cableLease) {
      sharedCable.release()
      this.cableLease = false
      this.consumer = null
    }
  }

  resubscribeToUpdates() {
    // Token renewal changes the subscription identifier, not the page socket.
    this.unsubscribeFromUpdates({ releaseConsumer: false })
    this.subscribeToUpdates()
  }

  handleChannelUpdate(data) {
    if (data.action === 'update') {
      const changes = data.changes || Object.fromEntries(
        Object.entries(data.props || {}).map(([name, value]) => [`prop.${name}`, { new: value }])
      )
      this.scheduleUpdate(changes)
    } else if (data.action === 'observed_change' && data.store) {
      this.scheduleUpdate({
        [`observed.${data.store}.__revision`]: { new: data.revision || Date.now() }
      })
    }
  }

  handleUpdateError(error) {
    // Show error in development
    if (this.isDevelopment()) {
      console.error('SwiftUI Reactive Update Error:', error)

      // Dispatch error event
      this.dispatch('update-error', {
        detail: { error, componentId: this.componentIdValue }
      })
    }
  }

  applyRenewedCapabilities(data = {}) {
    const renewedSnapshot = data.snapshot_token
    const renewedStreamToken = data.stream_token
    const streamTokenChanged = renewedStreamToken && renewedStreamToken !== this.streamTokenValue

    if (renewedSnapshot) this.snapshotTokenValue = renewedSnapshot
    if (renewedStreamToken) this.streamTokenValue = renewedStreamToken
    if (streamTokenChanged && this.channel) this.resubscribeToUpdates()
  }

  mergePendingChanges(changes, { preserveNewer = false } = {}) {
    if (!changes || typeof changes !== 'object') return

    this.pendingChanges = preserveNewer
      ? { ...changes, ...(this.pendingChanges || {}) }
      : { ...(this.pendingChanges || {}), ...changes }
  }

  hasPendingChanges() {
    return Object.keys(this.pendingChanges || {}).length > 0
  }

  isTransientError(error) {
    return !(error instanceof ReactiveResponseError) || TRANSIENT_RESPONSE_STATUSES.has(error.status)
  }

  isCapabilityError(error) {
    if (!(error instanceof ReactiveResponseError)) return false
    if (CAPABILITY_RESPONSE_STATUSES.has(error.status)) return true

    const message = typeof error.payload === 'object'
      ? error.payload?.error
      : error.payload
    return error.status === 422 && /authoriz|capabil|snapshot|expired|token/i.test(message || '')
  }

  capabilityReloadGuardKey() {
    return `swift-ui-reactive:capability-reload:${window.location.pathname}:${this.componentIdValue}`
  }

  recoverInvalidCapability(error) {
    if (this.capabilityRecoveryStarted) return
    this.capabilityRecoveryStarted = true

    const recoveryEvent = this.dispatch('capability-error', {
      detail: {
        status: error.status,
        error: error.payload,
        componentId: this.componentIdValue
      },
      bubbles: true,
      cancelable: true
    })
    if (recoveryEvent.defaultPrevented) return

    // One guarded reload obtains fresh server capabilities. Keep the guard in
    // sessionStorage across that reload; it is cleared only after a successful
    // reactive response, so a bad deployment cannot create a reload loop.
    try {
      const key = this.capabilityReloadGuardKey()
      const previousAttempt = Number(window.sessionStorage.getItem(key) || 0)
      if (Date.now() - previousAttempt < CAPABILITY_RELOAD_GUARD_MS) return

      window.sessionStorage.setItem(key, String(Date.now()))
      window.location.reload()
    } catch (_storageError) {
      // Sandboxed/private contexts may deny storage. The explicit event above
      // remains the recovery boundary in that case.
    }
  }

  clearCapabilityReloadGuard() {
    this.capabilityRecoveryStarted = false
    try {
      window.sessionStorage.removeItem(this.capabilityReloadGuardKey())
    } catch (_storageError) {
      // Storage is optional; successful capability renewal is still complete.
    }
  }

  waitForUpdateQueue() {
    const busy = this.updateInFlight || this.externalUpdates > 0 ||
      this.hasPendingChanges() || this.updateTimer || this.retryTimer
    if (!busy) return Promise.resolve(true)

    return new Promise(resolve => this.idleWaiters.push(resolve))
  }

  async flushPendingUpdates() {
    const completion = this.waitForUpdateQueue()
    if (!this.updateInFlight && this.externalUpdates === 0 && this.hasPendingChanges() && !this.retryTimer) {
      clearTimeout(this.updateTimer)
      this.updateTimer = null
      this.performUpdate()
    }
    return completion
  }

  resolveIdleWaiters(success) {
    const waiters = this.idleWaiters || []
    this.idleWaiters = []
    waiters.forEach(resolve => resolve(success))
  }

  beginExternalUpdate() {
    this.externalUpdates += 1
    clearTimeout(this.updateTimer)
    this.updateTimer = null
  }

  endExternalUpdate(success = true) {
    this.externalUpdates = Math.max(0, this.externalUpdates - 1)
    if (this.externalUpdates > 0) return

    if (success && this.hasPendingChanges()) {
      this.updateTimer = setTimeout(() => this.performUpdate(), 0)
    } else if (!this.hasPendingChanges()) {
      this.resolveIdleWaiters(success)
    } else if (!success) {
      this.resolveIdleWaiters(false)
    }
  }

  collectBindings() {
    const bindings = {}

    this.element.querySelectorAll('[data-sui-binding], [data-binding]').forEach(element => {
      const name = element.dataset.suiBinding || element.dataset.binding
      bindings[name] = this.readBindingValue(element)
    })

    return bindings
  }

  readBindingValue(element) {
    if (element.type === 'checkbox') return element.checked

    const value = element.value
    switch (element.dataset.suiBindingType || element.dataset.bindingType) {
      case 'integer': {
        if (value === '') return null
        const parsed = Number.parseInt(value, 10)
        return Number.isNaN(parsed) ? value : parsed
      }
      case 'float': {
        if (value === '') return null
        const parsed = Number.parseFloat(value)
        return Number.isNaN(parsed) ? value : parsed
      }
      case 'boolean':
        return value === 'true' || value === '1' || value === 'on'
      default:
        return value
    }
  }

  registerComponent() {
    // Register with global tracker
    if (!window.SwiftUIReactive) {
      window.SwiftUIReactive = {
        components: new Map(),
        register(element, config) {
          this.components.set(config.component_id, { element, config })
        },
        unregister(componentId) {
          this.components.delete(componentId)
        },
        updateStore(storeName, changes) {
          // Notify all components observing this store
          this.components.forEach(({ element, config }) => {
            const controller = element._swiftUIReactiveController
            if (controller && controller.storeSubscriptions?.[storeName]) {
              controller.handleStoreUpdate(storeName, changes)
            }
          })
        }
      }
    }

    window.SwiftUIReactive.register(this.element, {
      component_id: this.componentIdValue,
      component_class: this.componentClassValue,
      stream_token: this.streamTokenValue
    })

    // Store reference on element
    this.element._swiftUIReactiveController = this
  }

  unregisterComponent() {
    if (window.SwiftUIReactive) {
      window.SwiftUIReactive.unregister(this.componentIdValue)
    }
    delete this.element._swiftUIReactiveController
  }

  handleStoreUpdate(storeName, changes) {
    // Handle updates from observed stores
    const storeChanges = {}
    Object.entries(changes).forEach(([key, change]) => {
      storeChanges[`observed.${storeName}.${key}`] = change
    })

    this.scheduleUpdate(storeChanges)
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  dispatch(name, options = {}) {
    const event = new CustomEvent(`swift-ui-reactive:${name}`, {
      bubbles: options.bubbles !== false,
      cancelable: options.cancelable === true,
      detail: options.detail || {}
    })
    this.element.dispatchEvent(event)
    return event
  }

  isDevelopment() {
    return document.querySelector('meta[name="rails-env"]')?.content === 'development'
  }
}

const ROOT_SELECTOR = '[data-sui-root="1"], [data-swift-ui-reactive="true"]'
const ACTION_SELECTOR = '[data-sui-actions], [data-swift-ui-component-action-map-value]'
const BINDING_SELECTOR = '[data-sui-binding], [data-binding]'
const OBSERVED_BEHAVIOR_ATTRIBUTES = [
  'data-sui-root', 'data-sui-lifecycle', 'data-sui-task', 'data-sui-focus',
  'data-sui-keyboard-activate', 'data-sui-long-press', 'data-sui-drag',
  'data-sui-keypress', 'data-sui-tabs', 'data-sui-popover', 'data-sui-present',
  'data-sui-toolbar', 'data-sui-dialog', 'data-sui-workflow',
  'data-sui-async-image', 'data-sui-canvas'
]
const DELEGATED_EVENTS = [
  ...DELEGATED_ACTION_EVENTS,
  'direct-upload:initialize', 'direct-upload:start', 'direct-upload:progress',
  'direct-upload:error', 'direct-upload:end', 'turbo:submit-start', 'turbo:submit-end',
  'swift-ui-drag-start', 'swift-ui-drag-change',
  'swift-ui:refresh'
]

class BehaviorRegistry {
  constructor(runtime) {
    this.runtime = runtime
    this.definitions = new Map()
    this.instances = new Map()
  }

  register(name, definition) {
    if (!/^[a-z][a-z0-9-]{0,63}$/.test(name) || this.definitions.has(name)) {
      throw new TypeError(`Invalid or duplicate SwiftUI behavior: ${name}`)
    }
    this.definitions.set(name, Object.freeze({ ...definition, name }))
  }

  connectTree(tree) {
    for (const definition of this.definitions.values()) {
      const candidates = []
      if (tree instanceof Element && tree.matches(definition.selector)) candidates.push(tree)
      tree.querySelectorAll?.(definition.selector).forEach((element) => candidates.push(element))
      candidates.forEach((element) => this.connect(definition, element))
    }
  }

  connect(definition, element) {
    let elementInstances = this.instances.get(element)
    if (!elementInstances) {
      elementInstances = new Map()
      this.instances.set(element, elementInstances)
    }
    if (elementInstances.has(definition.name)) return

    const instance = definition.create(element, this.runtime)
    elementInstances.set(definition.name, instance)
    instance.connect?.()
  }

  refreshElement(element) {
    for (const definition of this.definitions.values()) {
      const instance = this.instances.get(element)?.get(definition.name)
      if (element.matches(definition.selector)) {
        if (instance) instance.update?.()
        else this.connect(definition, element)
      } else if (instance) {
        instance.disconnect?.()
        const elementInstances = this.instances.get(element)
        elementInstances.delete(definition.name)
        if (elementInstances.size === 0) this.instances.delete(element)
      }
    }
  }

  disconnectTree(tree) {
    const elements = []
    if (tree instanceof Element) elements.push(tree)
    tree.querySelectorAll?.('*').forEach((element) => elements.push(element))
    elements.forEach((element) => {
      const elementInstances = this.instances.get(element)
      if (!elementInstances) return
      elementInstances.forEach((instance) => instance.disconnect?.())
      this.instances.delete(element)
    })
  }

  handleEvent(event) {
    if (!(event.target instanceof Element)) return
    let element = event.target
    while (element) {
      const elementInstances = this.instances.get(element)
      elementInstances?.forEach((instance) => instance.handleEvent?.(event))
      element = element.parentElement
    }
  }
}

export class SwiftUIRuntime {
  constructor(rootDocument = document) {
    this.document = rootDocument
    this.transports = new WeakMap()
    this.connectedRoots = new Set()
    this.behaviors = new BehaviorRegistry(this)
    this.actions = new SwiftUIActionTransport(this)
    this.started = false
    this.handleEvent = this.handleEvent.bind(this)
    this.handleMutations = this.handleMutations.bind(this)
    this.handleTurboStreamRender = this.handleTurboStreamRender.bind(this)
    this.installBuiltinBehaviors()
  }

  start() {
    if (this.started) return this
    this.started = true
    DELEGATED_EVENTS.forEach((name) => this.document.addEventListener(name, this.handleEvent, true))
    this.document.addEventListener('turbo:before-stream-render', this.handleTurboStreamRender)
    this.connectTree(this.document)
    this.observer = new MutationObserver(this.handleMutations)
    this.observer.observe(this.document.documentElement, {
      attributeFilter: OBSERVED_BEHAVIOR_ATTRIBUTES,
      attributes: true,
      childList: true,
      subtree: true
    })
    this.document.dispatchEvent(new CustomEvent('swift-ui:ready', { detail: { runtime: this } }))
    return this
  }

  stop() {
    if (!this.started) return
    this.started = false
    this.observer?.disconnect()
    DELEGATED_EVENTS.forEach((name) => this.document.removeEventListener(name, this.handleEvent, true))
    this.document.removeEventListener('turbo:before-stream-render', this.handleTurboStreamRender)
    this.connectedRoots.forEach((root) => this.disconnectRoot(root))
    this.behaviors.disconnectTree(this.document.documentElement)
  }

  connectTree(tree) {
    const roots = []
    if (tree instanceof Element && tree.matches(ROOT_SELECTOR)) roots.push(tree)
    tree.querySelectorAll?.(ROOT_SELECTOR).forEach((root) => roots.push(root))
    roots.forEach((root) => this.connectRoot(root))
    this.behaviors.connectTree(tree)
  }

  connectRoot(root) {
    if (this.transports.has(root)) return this.transports.get(root)
    const transport = new SwiftUIReactiveTransport(root, this)
    this.transports.set(root, transport)
    this.connectedRoots.add(root)
    transport.connect()
    root._swiftUIReactiveController = transport // Compatibility-only diagnostic handle.
    root._swiftUITransport = transport
    return transport
  }

  disconnectRoot(root) {
    const transport = this.transports.get(root)
    if (!transport) return
    transport.disconnect()
    this.transports.delete(root)
    this.connectedRoots.delete(root)
    delete root._swiftUITransport
  }

  transportFor(root) {
    if (!(root instanceof Element)) return null
    return this.transports.get(root) || this.connectRoot(root)
  }

  handleMutations(mutations) {
    mutations.forEach((mutation) => {
      if (mutation.type === 'attributes') {
        const element = mutation.target
        if (!(element instanceof Element) || !mutation.attributeName?.startsWith('data-sui-')) return
        if (element.matches(ROOT_SELECTOR)) this.connectRoot(element)
        this.behaviors.refreshElement(element)
        return
      }
      mutation.addedNodes.forEach((node) => {
        if (node instanceof Element) this.connectTree(node)
      })
      mutation.removedNodes.forEach((node) => {
        if (!(node instanceof Element) || node.isConnected) return
        this.behaviors.disconnectTree(node)
        const roots = []
        if (node.matches(ROOT_SELECTOR)) roots.push(node)
        node.querySelectorAll(ROOT_SELECTOR).forEach((root) => roots.push(root))
        roots.forEach((root) => {
          if (!root.isConnected) this.disconnectRoot(root)
        })
      })
    })
  }

  handleEvent(event) {
    this.behaviors.handleEvent(event)
    this.handleBindingEvent(event)
    this.handleActionEvent(event)
  }

  handleTurboStreamRender(event) {
    const stream = event.target
    if (!stream || !['remove', 'replace', 'update'].includes(stream.action)) return
    const exiting = (stream.targetElements || []).filter((element) => element.dataset?.motionExit)
    if (exiting.length === 0 || typeof event.detail?.render !== 'function') return
    const defaultRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await Promise.all(exiting.map((element) => this.playExitTransition(element)))
      await defaultRender(streamElement)
    }
  }

  playExitTransition(element) {
    return new Promise((resolve) => {
      element.classList.add(element.dataset.motionExit)
      element.addEventListener('animationend', resolve, { once: true })
      setTimeout(resolve, EXIT_TRANSITION_FALLBACK_MS)
    })
  }

  handleBindingEvent(event) {
    if (!['input', 'change'].includes(event.type) || !(event.target instanceof Element)) return
    const target = event.target.closest(BINDING_SELECTOR)
    if (!target) return
    const root = target.closest(ROOT_SELECTOR)
    if (!root) return

    const expected = target.type === 'checkbox' || target.tagName === 'SELECT' ? 'change' : 'input'
    if (event.type !== expected) return
    const name = target.dataset.suiBinding || target.dataset.binding
    if (!name) return
    const transport = this.transportFor(root)
    transport.updateBinding(name, transport.readBindingValue(target))
  }

  handleActionEvent(event) {
    if (!DELEGATED_ACTION_EVENT_SET.has(event.type)) return
    if (!(event.target instanceof Element)) return
    const target = event.target.closest(ACTION_SELECTOR)
    if (!target) return
    const actionId = this.actions.findActionId(target, event.type)
    if (!actionId) return
    this.actions.handleAction(event, target)
  }

  performSemanticAction(element, eventType, detail = {}) {
    if (!(element instanceof Element) || !this.actions.findActionId(element, eventType)) return null
    return this.actions.handleAction({ type: eventType, detail }, element)
  }

  installBuiltinBehaviors() {
    this.behaviors.register('interaction', {
      selector: [
        '[data-sui-lifecycle]', '[data-sui-task]', '[data-sui-focus]',
        '[data-sui-keyboard-activate]', '[data-sui-long-press]',
        '[data-sui-drag]', '[data-sui-keypress]'
      ].join(','),
      create: (element, runtime) => new InteractionBehavior(element, runtime)
    })
    this.behaviors.register('presentation', {
      selector: '[data-sui-tabs], [data-sui-popover], [data-sui-present], [data-sui-toolbar], [data-sui-dialog]',
      create: (element) => new PresentationBehavior(element)
    })
    this.behaviors.register('workflow', {
      selector: '[data-sui-workflow]',
      create: (element) => new WorkflowBehavior(element)
    })
    this.behaviors.register('async-image', {
      selector: '[data-sui-async-image]',
      create: (element) => new AsyncImageBehavior(element)
    })
    this.behaviors.register('canvas', {
      selector: '[data-sui-canvas]',
      create: (element) => new CanvasBehavior(element)
    })
  }
}

function readJSONAttribute(element, name, fallback = null, maxBytes = 64 * 1024) {
  const source = element.getAttribute(name)
  if (!source) return fallback
  if (byteLength(source) > maxBytes) return fallback
  try {
    const value = JSON.parse(source)
    return value && typeof value === 'object' && !Array.isArray(value) ? value : fallback
  } catch (_error) {
    return fallback
  }
}

function dispatchSemantic(element, name, detail = {}, cancelable = false) {
  const event = new CustomEvent(name, { bubbles: true, cancelable, detail })
  element.dispatchEvent(event)
  return event
}

class InteractionBehavior {
  constructor(element, runtime) {
    this.element = element
    this.runtime = runtime
    this.connected = false
    this.longPressOrigin = null
    this.dragOrigin = null
  }

  connect() {
    this.connected = true
    this.focusWasActive = Boolean(this.focusConfig()?.active)
    const keypress = this.keypressConfig()
    if (keypress?.scope === 'window') {
      this.globalKeyHandler = (event) => this.filterKeyPress(event)
      document.addEventListener(keypress.phase === 'keyup' ? 'keyup' : 'keydown', this.globalKeyHandler)
    }

    queueMicrotask(() => {
      if (!this.connected || !this.element.isConnected) return
      const focus = this.focusConfig()
      if (focus?.active) this.requestFocus()
      if (this.element.dataset.suiLifecycle === '1') {
        this.emit('swift-ui-appear', this.lifecycleDetail())
      }
      const task = this.taskConfig()
      if (task && task.trigger !== 'manual') this.runTask()
    })
  }

  update() {
    const focusActive = Boolean(this.focusConfig()?.active)
    if (focusActive && !this.focusWasActive) queueMicrotask(() => this.requestFocus())
    this.focusWasActive = focusActive
  }

  disconnect() {
    if (this.element.dataset.suiLifecycle === '1') {
      const detail = this.lifecycleDetail()
      this.emit('swift-ui-disappear', detail)
      if (!this.element.isConnected) {
        this.runtime.performSemanticAction(this.element, 'swift-ui-disappear', detail)
      }
    }
    this.connected = false
    this.abortTask()
    this.cancelLongPress()
    this.resetDrag()
    if (this.globalKeyHandler) {
      const keypress = this.keypressConfig()
      document.removeEventListener(keypress?.phase === 'keyup' ? 'keyup' : 'keydown', this.globalKeyHandler)
    }
  }

  handleEvent(event) {
    if (event.type === 'swift-ui:refresh') return this.runTask()
    if (event.type === 'focusin' || event.type === 'focusout') return this.focusChanged(event)

    if (this.element.dataset.suiKeyboardActivate === '1' && event.type === 'keydown') {
      this.activate(event)
    }

    if (this.longPressConfig()) {
      if (event.type === 'pointerdown') this.startLongPress(event)
      if (event.type === 'pointermove') this.moveLongPress(event)
      if (event.type === 'pointerup') this.finishLongPress()
      if (event.type === 'pointercancel') this.cancelLongPress()
      if (event.type === 'keydown') this.startKeyboardLongPress(event)
      if (event.type === 'keyup') this.finishKeyboardLongPress(event)
      if (event.type === 'click') this.suppressClick(event)
    }

    if (this.dragConfig()) {
      if (event.type === 'pointerdown') this.startDrag(event)
      if (event.type === 'pointermove') this.moveDrag(event)
      if (event.type === 'pointerup') this.finishDrag(event)
      if (event.type === 'pointercancel') this.cancelDrag()
      if (event.type === 'keydown') this.keyboardDrag(event)
    }

    const keypress = this.keypressConfig()
    if (keypress && keypress.scope !== 'window') {
      const expectedType = keypress.phase === 'keyup' ? 'keyup' : 'keydown'
      if (event.type === expectedType) this.filterKeyPress(event)
    }
  }

  lifecycleDetail() {
    return { id: this.element.dataset.suiLifecycleId || null }
  }

  focusConfig() {
    return readJSONAttribute(this.element, 'data-sui-focus')
  }

  taskConfig() {
    return readJSONAttribute(this.element, 'data-sui-task')
  }

  longPressConfig() {
    return readJSONAttribute(this.element, 'data-sui-long-press')
  }

  dragConfig() {
    return readJSONAttribute(this.element, 'data-sui-drag')
  }

  keypressConfig() {
    return readJSONAttribute(this.element, 'data-sui-keypress')
  }

  requestFocus() {
    if (this.isDisabled() || typeof this.element.focus !== 'function') return
    try {
      this.element.focus({ preventScroll: true })
    } catch (_error) {
      this.element.focus()
    }
  }

  focusChanged(event) {
    const config = this.focusConfig()
    if (!config) return
    const focused = event.type === 'focusin'
    this.element.dataset.suiFocusState = focused ? 'focused' : 'unfocused'
    const detail = { key: config.key || null, value: config.value || null, focused }
    const scope = this.element.closest('[data-sui-focus-scope]')
    if (scope && focused) {
      scope.dataset.suiFocusKey = detail.key || ''
      scope.dataset.suiFocusValue = detail.value || ''
    }
    dispatchSemantic(scope || this.element, 'swift-ui-focus-change', detail)
  }

  activate(event) {
    if (event.repeat || this.isDisabled() || this.longPressConfig()) return
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    const eventName = this.element.dataset.suiTap === '2' ? 'dblclick' : 'click'
    this.element.dispatchEvent(new MouseEvent(eventName, { bubbles: true, cancelable: true, view: window }))
  }

  startLongPress(event) {
    if (event.isPrimary === false || this.isDisabled()) return
    this.beginLongPress({
      clientX: event.clientX,
      clientY: event.clientY,
      pointerType: event.pointerType || 'pointer'
    })
  }

  moveLongPress(event) {
    if (!this.longPressOrigin) return
    const config = this.longPressConfig() || {}
    const distance = Math.hypot(
      event.clientX - this.longPressOrigin.clientX,
      event.clientY - this.longPressOrigin.clientY
    )
    if (distance > Number(config.distance || 10)) this.cancelLongPress()
  }

  finishLongPress() {
    this.clearLongPressTimer()
    this.longPressOrigin = null
    if (!this.suppressNextClick) return
    clearTimeout(this.clickSuppressionTimer)
    this.clickSuppressionTimer = setTimeout(() => {
      this.suppressNextClick = false
      this.clickSuppressionTimer = null
    }, 0)
  }

  cancelLongPress() {
    this.clearLongPressTimer()
    this.longPressOrigin = null
    this.suppressNextClick = false
    clearTimeout(this.clickSuppressionTimer)
  }

  startKeyboardLongPress(event) {
    if (event.repeat || this.isDisabled() || !['Enter', ' '].includes(event.key)) return
    event.preventDefault()
    this.beginLongPress({ clientX: 0, clientY: 0, pointerType: 'keyboard' })
  }

  finishKeyboardLongPress(event) {
    if (!['Enter', ' '].includes(event.key)) return
    event.preventDefault()
    const started = Boolean(this.longPressOrigin)
    const recognized = this.suppressNextClick
    this.finishLongPress()
    if (started && !recognized && this.element.dataset.suiKeyboardActivate === '1') {
      const eventName = this.element.dataset.suiTap === '2' ? 'dblclick' : 'click'
      this.element.dispatchEvent(new MouseEvent(eventName, { bubbles: true, cancelable: true, view: window }))
    }
  }

  beginLongPress(origin) {
    this.cancelLongPress()
    this.longPressOrigin = origin
    const duration = Math.max(0, Number(this.longPressConfig()?.duration || 500))
    this.longPressTimer = setTimeout(() => {
      if (!this.longPressOrigin) return
      this.suppressNextClick = true
      this.element.dataset.suiLongPressState = 'recognized'
      this.emit('swift-ui-long-press', { duration, pointerType: this.longPressOrigin.pointerType })
    }, duration)
  }

  clearLongPressTimer() {
    clearTimeout(this.longPressTimer)
    this.longPressTimer = null
  }

  suppressClick(event) {
    if (!this.suppressNextClick) return
    this.suppressNextClick = false
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  startDrag(event) {
    if (event.isPrimary === false || this.isDisabled()) return
    this.dragPointerId = event.pointerId
    this.dragOrigin = { x: event.clientX, y: event.clientY }
    this.dragActive = false
    try {
      this.element.setPointerCapture(event.pointerId)
    } catch (_error) {
      // Pointer capture is an optional enhancement.
    }
  }

  moveDrag(event) {
    if (!this.dragOrigin || event.pointerId !== this.dragPointerId) return
    const translation = this.dragTranslation(event.clientX, event.clientY)
    const threshold = Number(this.dragConfig()?.distance || 10)
    if (!this.dragActive && Math.hypot(translation.x, translation.y) < threshold) return
    if (!this.dragActive) {
      this.dragActive = true
      this.emitDrag('swift-ui-drag-start', { x: 0, y: 0 })
    }
    event.preventDefault()
    this.emitDrag('swift-ui-drag-change', translation)
  }

  finishDrag(event) {
    if (!this.dragOrigin || event.pointerId !== this.dragPointerId) return
    if (this.dragActive) this.emitDrag('swift-ui-drag-end', this.dragTranslation(event.clientX, event.clientY))
    this.resetDrag()
  }

  cancelDrag() {
    if (this.dragActive) this.emitDrag('swift-ui-drag-end', this.currentDragTranslation(), { cancelled: true })
    this.resetDrag()
  }

  keyboardDrag(event) {
    if (this.isDisabled()) return
    const directions = {
      ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]
    }
    const direction = directions[event.key]
    if (!direction) return
    const config = this.dragConfig() || {}
    const axis = config.axis || 'both'
    if ((axis === 'horizontal' && direction[1]) || (axis === 'vertical' && direction[0])) return
    event.preventDefault()
    const step = Number(config.keyboardStep || 1)
    const translation = { x: direction[0] * step, y: direction[1] * step }
    this.emitDrag('swift-ui-drag-start', { x: 0, y: 0 }, { input: 'keyboard' })
    this.emitDrag('swift-ui-drag-change', translation, { input: 'keyboard' })
    this.emitDrag('swift-ui-drag-end', translation, { input: 'keyboard' })
  }

  dragTranslation(clientX, clientY) {
    const axis = this.dragConfig()?.axis || 'both'
    return {
      x: axis === 'vertical' ? 0 : clientX - this.dragOrigin.x,
      y: axis === 'horizontal' ? 0 : clientY - this.dragOrigin.y
    }
  }

  currentDragTranslation() {
    return {
      x: Number(this.element.dataset.suiDragTranslationX || 0),
      y: Number(this.element.dataset.suiDragTranslationY || 0)
    }
  }

  emitDrag(name, translation, extra = {}) {
    this.element.dataset.suiDragPhase = name.replace('swift-ui-drag-', '')
    this.element.dataset.suiDragTranslationX = String(translation.x)
    this.element.dataset.suiDragTranslationY = String(translation.y)
    this.emit(name, { translation, ...extra })
  }

  resetDrag() {
    this.dragPointerId = null
    this.dragOrigin = null
    this.dragActive = false
  }

  filterKeyPress(event) {
    if (this.isDisabled()) return
    const config = this.keypressConfig()
    if (!config || !Array.isArray(config.keys)) return
    const normalized = event.key.length === 1 && event.key !== ' ' ? event.key.toLowerCase() : event.key
    if (!config.keys.includes(normalized)) return
    const modifiers = Array.isArray(config.modifiers) ? config.modifiers : []
    const modifierState = {
      alt: event.altKey, control: event.ctrlKey, meta: event.metaKey, shift: event.shiftKey
    }
    if (!modifiers.every((modifier) => modifierState[modifier])) return
    if (config.preventDefault) event.preventDefault()
    this.element.dataset.suiKey = normalized
    this.emit('swift-ui-key-press', {
      key: normalized,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      metaKey: event.metaKey,
      shiftKey: event.shiftKey
    })
  }

  async runTask() {
    const config = this.taskConfig()
    if (!config?.url) return
    let url
    try {
      url = new URL(config.url, window.location.href)
    } catch (_error) {
      return
    }
    if (url.origin !== window.location.origin || !['http:', 'https:'].includes(url.protocol)) return

    this.abortTask()
    const abortController = new AbortController()
    this.taskAbortController = abortController
    this.element.dataset.suiTaskState = 'loading'
    this.element.setAttribute('aria-busy', 'true')
    this.emit('swift-ui-task-start', this.taskDetail())
    try {
      const method = String(config.method || 'GET').toUpperCase()
      if (!['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) throw new Error('Unsupported task method')
      const response = await fetch(url.href, {
        method,
        credentials: 'same-origin',
        redirect: 'error',
        headers: this.taskHeaders(method),
        signal: abortController.signal
      })
      if (!response.ok) throw new Error(`Task failed with HTTP ${response.status}`)
      const result = await this.readTaskResponse(response)
      if (!this.connected || this.taskAbortController !== abortController) return
      if (config.response === 'replace_content' && result.kind === 'html') this.element.innerHTML = result.value
      this.element.dataset.suiTaskState = 'success'
      this.emit('swift-ui-task-success', { ...this.taskDetail(), result })
    } catch (error) {
      if (error.name === 'AbortError') return
      this.element.dataset.suiTaskState = 'failure'
      this.emit('swift-ui-task-failure', { ...this.taskDetail(), message: error.message })
    } finally {
      if (this.taskAbortController === abortController) {
        if (this.connected) this.element.removeAttribute('aria-busy')
        this.taskAbortController = null
      }
    }
  }

  taskHeaders(method) {
    const headers = { Accept: 'application/json, text/html, text/plain' }
    if (method !== 'GET') {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (token) headers['X-CSRF-Token'] = token
    }
    return headers
  }

  async readTaskResponse(response) {
    const contentType = response.headers.get('content-type') || ''
    const text = await response.text()
    if (byteLength(text) > 1_000_000) throw new Error('Task response exceeds 1 MB')
    if (contentType.includes('application/json')) return { kind: 'json', value: JSON.parse(text) }
    if (contentType.includes('text/html')) return { kind: 'html', value: text }
    return { kind: 'text', value: text }
  }

  taskDetail() {
    return { id: this.element.dataset.suiLifecycleId || null, url: this.taskConfig()?.url }
  }

  abortTask() {
    this.taskAbortController?.abort()
    this.taskAbortController = null
  }

  isDisabled() {
    return this.element.disabled || this.element.getAttribute('aria-disabled') === 'true'
  }

  emit(name, detail = {}) {
    return dispatchSemantic(this.element, name, detail)
  }
}

class PresentationBehavior {
  constructor(element) {
    this.element = element
  }

  connect() {
    if (this.element.hasAttribute('data-sui-tabs')) this.initializeTabs()
    if (this.element.hasAttribute('data-sui-popover')) this.initializePopover()
    if (this.element.hasAttribute('data-sui-toolbar')) this.initializeToolbar()
    if (this.element.hasAttribute('data-sui-dialog')) this.initializeDialog()
  }

  update() {
    if (this.element.hasAttribute('data-sui-tabs')) {
      const selected = this.tabForValue(this.tabsConfig().selection)
      if (selected) this.activateTab(selected, { focus: false, historyMode: null })
    }
    if (this.element.hasAttribute('data-sui-toolbar')) this.scheduleToolbarLayout()
    if (this.element.hasAttribute('data-sui-dialog')) {
      const presented = this.dialogConfig().presented
      if (presented) this.showDialog(this.element)
      if (!presented && this.element.open) this.element.close('server')
    }
  }

  disconnect() {
    if (this.outsidePointerHandler) document.removeEventListener('pointerdown', this.outsidePointerHandler)
    if (this.tabLocationHandler) {
      window.removeEventListener('popstate', this.tabLocationHandler)
      window.removeEventListener('hashchange', this.tabLocationHandler)
    }
    this.teardownToolbar()
  }

  handleEvent(event) {
    if (this.element.hasAttribute('data-sui-present') && event.type === 'click') return this.open(event)

    if (this.element.hasAttribute('data-sui-tabs')) {
      const tab = event.target.closest?.('[data-sui-tab]')
      if (tab && tab.closest('[data-sui-tabs]') === this.element) {
        if (event.type === 'click') this.selectTab(event, tab)
        if (event.type === 'keydown') this.navigateTabs(event, tab)
      }
    }

    if (this.element.hasAttribute('data-sui-popover')) {
      if (event.type === 'toggle') this.syncPopover()
      if (event.type === 'keydown' && event.key === 'Escape') this.closePopover(event)
    }

    if (this.element.hasAttribute('data-sui-toolbar')) {
      if (event.type === 'keydown') this.navigateToolbar(event)
      if (event.type === 'toggle') this.syncToolbarOverflow(event)
    }

    if (this.element.hasAttribute('data-sui-dialog')) {
      if (event.type === 'cancel') this.handleCancel(event)
      if (event.type === 'click') this.closeOnBackdrop(event)
      if (event.type === 'close') this.restoreFocus()
    }
  }

  tabsConfig() {
    return readJSONAttribute(this.element, 'data-sui-tabs', {}) || {}
  }

  toolbarConfig() {
    return readJSONAttribute(this.element, 'data-sui-toolbar', {}) || {}
  }

  dialogConfig() {
    return readJSONAttribute(this.element, 'data-sui-dialog', {}) || {}
  }

  open(event) {
    const targetId = this.element.dataset.suiPresent
    if (!targetId) return
    const dialog = document.getElementById(targetId)
    if (!(dialog instanceof HTMLDialogElement) || !dialog.hasAttribute('data-sui-dialog')) return
    event.preventDefault()
    dialog.swiftUIReturnFocusElement = this.element
    this.showDialog(dialog)
  }

  handleCancel(event) {
    if (this.dialogConfig().dismissible === false) event.preventDefault()
  }

  closeOnBackdrop(event) {
    if (event.target !== this.element || this.dialogConfig().dismissible === false) return
    this.element.close('backdrop')
  }

  restoreFocus() {
    const target = this.element.swiftUIReturnFocusElement || this.previouslyFocusedElement
    if (target instanceof HTMLElement && target.isConnected) target.focus()
  }

  initializeDialog() {
    this.previouslyFocusedElement = document.activeElement
    const config = this.dialogConfig()
    if (config.presented || this.element.hasAttribute('open')) this.showDialog(this.element)
  }

  showDialog(dialog) {
    try {
      if (dialog.matches(':modal')) return
    } catch (_error) {
      // Older engines do not implement :modal.
    }
    if (dialog.hasAttribute('open')) dialog.removeAttribute('open')
    if (typeof dialog.showModal === 'function') {
      try {
        dialog.showModal()
        dialog.setAttribute('aria-modal', 'true')
        return
      } catch (_error) {
        // Detached dialogs retain the semantic open fallback.
      }
    }
    dialog.setAttribute('aria-modal', 'false')
    dialog.setAttribute('open', '')
  }

  initializeTabs() {
    this.element.dataset.suiEnhanced = 'tabs'
    const tabs = this.enabledTabs()
    const config = this.tabsConfig()
    const serverSelected = tabs.find((tab) => tab.getAttribute('aria-selected') === 'true') || tabs[0]
    this.initialTabValue = config.initialSelection || this.tabConfig(serverSelected)?.value
    const selected = this.tabForCurrentLocation() || this.tabForValue(config.selection) || serverSelected
    if (selected) this.activateTab(selected, { focus: false, historyMode: null })
    this.tabLocationHandler = () => this.restoreTabFromLocation()
    window.addEventListener('popstate', this.tabLocationHandler)
    window.addEventListener('hashchange', this.tabLocationHandler)
  }

  tabConfig(tab) {
    return tab ? readJSONAttribute(tab, 'data-sui-tab', {}) || {} : {}
  }

  panelConfig(panel) {
    return panel ? readJSONAttribute(panel, 'data-sui-tab-panel', {}) || {} : {}
  }

  enabledTabs() {
    return Array.from(this.element.querySelectorAll('[data-sui-tab][role="tab"]')).filter((tab) => {
      return tab.closest('[data-sui-tabs]') === this.element && tab.getAttribute('aria-disabled') !== 'true'
    })
  }

  tabPanels() {
    return Array.from(this.element.querySelectorAll('[data-sui-tab-panel]')).filter((panel) => {
      return panel.closest('[data-sui-tabs]') === this.element
    })
  }

  tabPanel(tab) {
    if (!this.enabledTabs().includes(tab)) return null
    const value = this.tabConfig(tab).value
    const panelId = tab.getAttribute('aria-controls')
    return this.tabPanels().find((panel) => {
      return panel.id === panelId && this.panelConfig(panel).value === value
    }) || null
  }

  localTabPanel(tab) {
    return this.tabConfig(tab).local === false ? null : this.tabPanel(tab)
  }

  selectTab(event, tab) {
    if (!this.localTabPanel(tab)) return
    event.preventDefault()
    this.activateTab(tab, { focus: true, historyMode: 'push' })
  }

  navigateTabs(event, currentTab) {
    const tabs = this.enabledTabs()
    const currentIndex = tabs.indexOf(currentTab)
    if (currentIndex < 0) return
    const vertical = this.element.getAttribute('aria-orientation') === 'vertical'
    let nextIndex
    if (event.key === (vertical ? 'ArrowUp' : 'ArrowLeft')) nextIndex = (currentIndex - 1 + tabs.length) % tabs.length
    if (event.key === (vertical ? 'ArrowDown' : 'ArrowRight')) nextIndex = (currentIndex + 1) % tabs.length
    if (event.key === 'Home') nextIndex = 0
    if (event.key === 'End') nextIndex = tabs.length - 1
    if (nextIndex === undefined) return
    event.preventDefault()
    const nextTab = tabs[nextIndex]
    nextTab.focus()
    if (this.localTabPanel(nextTab)) this.activateTab(nextTab, { focus: false, historyMode: 'push' })
  }

  activateTab(tab, { focus, historyMode }) {
    const panel = this.tabPanel(tab)
    if (!panel) return false
    const value = this.tabConfig(tab).value
    const previousValue = this.element.dataset.suiSelection
    this.enabledTabs().forEach((candidate) => {
      const selected = candidate === tab
      candidate.setAttribute('aria-selected', String(selected))
      candidate.tabIndex = selected ? 0 : -1
    })
    this.tabPanels().forEach((candidate) => { candidate.hidden = candidate !== panel })
    if (focus) tab.focus()
    if (historyMode === 'push' && panel.id && window.location.hash !== `#${panel.id}`) {
      history.pushState(history.state, '', `#${panel.id}`)
    }
    this.element.dataset.suiSelection = value || ''
    if (previousValue !== value) dispatchSemantic(this.element, 'swift-ui-tab-change', { selection: value })
    return true
  }

  tabForCurrentLocation() {
    if (!window.location.hash) return null
    let targetId
    try {
      targetId = decodeURIComponent(window.location.hash.slice(1))
    } catch (_error) {
      return null
    }
    return this.enabledTabs().find((tab) => this.localTabPanel(tab)?.id === targetId) || null
  }

  tabForValue(value) {
    return this.enabledTabs().find((tab) => this.tabConfig(tab).value === value && this.tabPanel(tab)) || null
  }

  restoreTabFromLocation() {
    const tab = this.tabForCurrentLocation() || this.tabForValue(this.initialTabValue)
    if (tab) this.activateTab(tab, { focus: false, historyMode: null })
  }

  initializePopover() {
    this.syncPopover()
    this.outsidePointerHandler = (event) => {
      if (this.element.open && !this.element.contains(event.target)) this.element.open = false
    }
    document.addEventListener('pointerdown', this.outsidePointerHandler)
  }

  closePopover(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.element.querySelector('summary')?.focus()
  }

  syncPopover() {
    this.element.querySelector('summary')?.setAttribute('aria-expanded', String(this.element.open))
  }

  initializeToolbar() {
    this.toolbarOriginalTabIndexes = new Map()
    this.toolbarItems().forEach((item, index) => { item.dataset.suiToolbarOrder = String(index) })
    this.toolbarMinimized = false
    this.element.dataset.suiEnhanced = 'toolbar'
    this.redistributeToolbar()
    this.toolbarResizeHandler = () => this.scheduleToolbarLayout()
    if (typeof ResizeObserver === 'function') {
      this.toolbarResizeObserver = new ResizeObserver(this.toolbarResizeHandler)
      this.toolbarResizeObserver.observe(this.element)
    } else {
      window.addEventListener('resize', this.toolbarResizeHandler)
    }
    if (this.toolbarConfig().minimizeOnScroll) this.initializeToolbarScrollMinimization()
  }

  toolbarRole(role) {
    return this.element.querySelector(`[data-sui-toolbar-role="${role}"]`)
  }

  toolbarItems() {
    return Array.from(this.element.querySelectorAll('.swift-ui-toolbar-item, [data-sui-toolbar-placement]')).filter((item) => {
      return item.closest('[data-sui-toolbar]') === this.element
    })
  }

  toolbarControls() {
    const selector = 'button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex]:not([tabindex="-1"])'
    return Array.from(this.element.querySelectorAll(selector)).filter((control, index, controls) => {
      const disclosure = control.closest('details')
      const visible = !control.closest('[hidden]') && (!disclosure || disclosure.open || control.tagName === 'SUMMARY')
      return controls.indexOf(control) === index && visible &&
        control.getAttribute('aria-disabled') !== 'true' && control.closest('[data-sui-toolbar]') === this.element
    })
  }

  navigateToolbar(event) {
    const controls = this.toolbarControls()
    const current = controls.find((control) => control === event.target || control.contains(event.target))
    const currentIndex = controls.indexOf(current)
    if (currentIndex < 0) return
    const vertical = this.toolbarConfig().orientation === 'vertical'
    let nextIndex
    if (event.key === (vertical ? 'ArrowUp' : 'ArrowLeft')) nextIndex = (currentIndex - 1 + controls.length) % controls.length
    if (event.key === (vertical ? 'ArrowDown' : 'ArrowRight')) nextIndex = (currentIndex + 1) % controls.length
    if (event.key === 'Home') nextIndex = 0
    if (event.key === 'End') nextIndex = controls.length - 1
    if (nextIndex === undefined) return
    event.preventDefault()
    controls.forEach((control, index) => { control.tabIndex = index === nextIndex ? 0 : -1 })
    controls[nextIndex].focus()
  }

  syncToolbarOverflow(event) {
    const disclosure = event.target.closest?.('[data-sui-toolbar-role="overflow"]')
    if (!(disclosure instanceof HTMLDetailsElement) || !this.element.contains(disclosure)) return
    const focused = document.activeElement
    if (!disclosure.open && focused instanceof HTMLElement && disclosure.contains(focused)) {
      disclosure.querySelector('summary')?.focus()
    }
    this.refreshToolbarFocus()
  }

  scheduleToolbarLayout() {
    cancelAnimationFrame(this.toolbarLayoutFrame)
    this.toolbarLayoutFrame = requestAnimationFrame(() => {
      this.toolbarLayoutFrame = null
      this.redistributeToolbar()
    })
  }

  redistributeToolbar() {
    const itemsContainer = this.toolbarRole('items')
    const disclosure = this.toolbarRole('overflow')
    const overflowContainer = this.toolbarRole('overflow-items')
    if (!itemsContainer || !disclosure || !overflowContainer) return
    const items = this.toolbarItems().sort((a, b) => Number(a.dataset.suiToolbarOrder) - Number(b.dataset.suiToolbarOrder))
    this.placeToolbarItems(itemsContainer, items)
    disclosure.hidden = true
    const config = this.toolbarConfig()
    if (config.overflow !== false) {
      items.filter((item) => this.toolbarVisibility(item) === 'overflow').forEach((item) => overflowContainer.append(item))
      disclosure.hidden = overflowContainer.children.length === 0
      if (this.toolbarMinimized) {
        items.filter((item) => this.toolbarItemCanOverflow(item)).forEach((item) => overflowContainer.append(item))
      } else {
        this.toolbarOverflowCandidates(items).forEach((item) => {
          if (this.toolbarIsClipped(itemsContainer)) overflowContainer.append(item)
        })
      }
    }
    this.sortToolbarContainer(itemsContainer)
    this.sortToolbarContainer(overflowContainer)
    disclosure.hidden = overflowContainer.children.length === 0
    if (disclosure.hidden) disclosure.open = false
    this.element.dataset.suiToolbarConstrained = String(this.toolbarIsClipped(itemsContainer))
    this.element.dataset.suiToolbarMinimized = String(this.toolbarMinimized)
    this.refreshToolbarFocus()
  }

  toolbarOverflowCandidates(items) {
    const rank = { low: 0, automatic: 1, high: 2 }
    return items.filter((item) => this.toolbarItemCanOverflow(item)).sort((left, right) => {
      const priority = (rank[this.toolbarPriority(left)] ?? 1) - (rank[this.toolbarPriority(right)] ?? 1)
      return priority || Number(right.dataset.suiToolbarOrder) - Number(left.dataset.suiToolbarOrder)
    })
  }

  toolbarItemCanOverflow(item) {
    return this.toolbarPriority(item) !== 'pinned' && this.toolbarVisibility(item) !== 'visible'
  }

  toolbarPriority(item) {
    return item.dataset.suiToolbarPriority || item.dataset.swiftUiToolbarPriority || 'automatic'
  }

  toolbarVisibility(item) {
    return item.dataset.suiToolbarVisibility || item.dataset.swiftUiToolbarVisibility || 'automatic'
  }

  sortToolbarContainer(container) {
    const items = Array.from(container.children).sort((left, right) => {
      return Number(left.dataset.suiToolbarOrder) - Number(right.dataset.suiToolbarOrder)
    })
    this.placeToolbarItems(container, items)
  }

  placeToolbarItems(container, items) {
    items.forEach((item, index) => {
      const current = container.children[index]
      if (current !== item) container.insertBefore(item, current || null)
    })
  }

  toolbarIsClipped(container) {
    return this.toolbarConfig().orientation === 'vertical'
      ? container.scrollHeight > container.clientHeight + 1
      : container.scrollWidth > container.clientWidth + 1
  }

  refreshToolbarFocus(preferred = document.activeElement) {
    const controls = this.toolbarControls()
    if (controls.length === 0) return
    controls.forEach((control) => {
      if (!this.toolbarOriginalTabIndexes.has(control)) {
        this.toolbarOriginalTabIndexes.set(control, control.getAttribute('tabindex'))
      }
    })
    const active = controls.includes(preferred) ? preferred : controls[0]
    controls.forEach((control) => { control.tabIndex = control === active ? 0 : -1 })
  }

  initializeToolbarScrollMinimization() {
    this.toolbarScrollSource = this.nearestScrollSource()
    this.toolbarLastScrollPosition = this.toolbarScrollPosition()
    this.toolbarScrollAnchor = this.toolbarLastScrollPosition
    this.toolbarScrollDirection = 0
    this.toolbarScrollHandler = () => this.handleToolbarScroll()
    this.toolbarScrollSource.addEventListener('scroll', this.toolbarScrollHandler, { passive: true })
  }

  nearestScrollSource() {
    let ancestor = this.element.parentElement
    while (ancestor) {
      const overflowY = getComputedStyle(ancestor).overflowY
      if (/(auto|scroll|overlay)/.test(overflowY) && ancestor.scrollHeight > ancestor.clientHeight) return ancestor
      ancestor = ancestor.parentElement
    }
    return window
  }

  toolbarScrollPosition() {
    return this.toolbarScrollSource === window ? window.scrollY : this.toolbarScrollSource?.scrollTop || 0
  }

  handleToolbarScroll() {
    cancelAnimationFrame(this.toolbarScrollFrame)
    this.toolbarScrollFrame = requestAnimationFrame(() => {
      const current = this.toolbarScrollPosition()
      const direction = Math.sign(current - this.toolbarLastScrollPosition)
      const threshold = Math.max(0, Number(this.toolbarConfig().minimizeThreshold || 24))
      if (current <= threshold) {
        this.setToolbarMinimized(false)
        this.toolbarScrollAnchor = current
      } else if (direction !== 0) {
        if (direction !== this.toolbarScrollDirection) this.toolbarScrollAnchor = this.toolbarLastScrollPosition
        if (Math.abs(current - this.toolbarScrollAnchor) >= threshold) {
          this.setToolbarMinimized(direction > 0)
          this.toolbarScrollAnchor = current
        }
      }
      this.toolbarScrollDirection = direction
      this.toolbarLastScrollPosition = current
    })
  }

  setToolbarMinimized(value) {
    if (this.toolbarMinimized === value) return
    this.toolbarMinimized = value
    this.scheduleToolbarLayout()
  }

  teardownToolbar() {
    if (!this.element.hasAttribute('data-sui-toolbar')) return
    cancelAnimationFrame(this.toolbarLayoutFrame)
    cancelAnimationFrame(this.toolbarScrollFrame)
    this.toolbarResizeObserver?.disconnect()
    if (this.toolbarResizeHandler && !this.toolbarResizeObserver) window.removeEventListener('resize', this.toolbarResizeHandler)
    if (this.toolbarScrollSource && this.toolbarScrollHandler) {
      this.toolbarScrollSource.removeEventListener('scroll', this.toolbarScrollHandler)
    }
    const itemsContainer = this.toolbarRole('items')
    if (itemsContainer) this.placeToolbarItems(itemsContainer, this.toolbarItems().sort((a, b) => {
      return Number(a.dataset.suiToolbarOrder) - Number(b.dataset.suiToolbarOrder)
    }))
    this.toolbarOriginalTabIndexes?.forEach((value, control) => {
      if (value === null) control.removeAttribute('tabindex')
      else control.setAttribute('tabindex', value)
    })
  }
}

class WorkflowBehavior {
  constructor(element) {
    this.element = element
    this.config = readJSONAttribute(element, 'data-sui-workflow', {}) || {}
  }

  connect() {
    this.draggedItem = null
    this.dragTarget = null
    this.swipePointer = null
  }

  update() {
    this.config = readJSONAttribute(this.element, 'data-sui-workflow', {}) || {}
  }

  disconnect() {
    this.clearDragState()
    this.swipePointer = null
  }

  handleEvent(event) {
    if (this.config.kind === 'reorder') this.handleReorderEvent(event)
    if (this.config.kind === 'swipe') this.handleSwipeEvent(event)
    if (this.config.kind === 'document') this.handleDocumentEvent(event)
  }

  role(name) {
    return this.element.querySelector(`[data-sui-workflow-role="${name}"]`)
  }

  roleForEvent(event, name) {
    const target = event.target instanceof Element
      ? event.target.closest(`[data-sui-workflow-role="${name}"]`)
      : null
    return target && target.closest('[data-sui-workflow]') === this.element ? target : null
  }

  handleReorderEvent(event) {
    if (event.type === 'dragstart') this.dragstart(event)
    if (event.type === 'dragover') this.dragover(event)
    if (event.type === 'drop') this.drop(event)
    if (event.type === 'dragend') this.clearDragState()
  }

  dragstart(event) {
    if (this.config.drag === false || !this.role('drag-form')) return
    const item = this.roleForEvent(event, 'reorder-item')
    if (!item) return
    const key = item.dataset.suiWorkflowKey
    if (!key) {
      event.preventDefault()
      return
    }
    this.draggedItem = item
    item.dataset.suiDragState = 'dragging'
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move'
      event.dataTransfer.setData('text/plain', key)
    }
  }

  dragover(event) {
    if (!this.draggedItem) return
    const item = this.roleForEvent(event, 'reorder-item')
    if (!item || item === this.draggedItem) return
    event.preventDefault()
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
    if (this.dragTarget && this.dragTarget !== item) delete this.dragTarget.dataset.suiDropState
    this.dragTarget = item
    item.dataset.suiDropState = this.dropPlacement(event, item)
  }

  drop(event) {
    const form = this.role('drag-form')
    if (!this.draggedItem || !this.dragTarget || !form) return
    event.preventDefault()
    const itemKey = this.draggedItem.dataset.suiWorkflowKey
    const targetKey = this.dragTarget.dataset.suiWorkflowKey
    if (!itemKey || !targetKey || itemKey === targetKey) return this.clearDragState()
    const itemInput = this.role('drag-item-key')
    const targetInput = this.role('drag-target-key')
    const placementInput = this.role('drag-placement')
    if (!itemInput || !targetInput || !placementInput) return this.clearDragState()
    itemInput.value = itemKey
    targetInput.value = targetKey
    placementInput.value = this.dropPlacement(event, this.dragTarget)
    form.requestSubmit()
    this.clearDragState()
  }

  dropPlacement(event, item) {
    const rect = item.getBoundingClientRect()
    if (this.config.layout === 'grid') {
      const leftHalf = event.clientX < rect.left + rect.width / 2
      const rtl = getComputedStyle(this.element).direction === 'rtl'
      return (rtl ? !leftHalf : leftHalf) ? 'before' : 'after'
    }
    return event.clientY < rect.top + rect.height / 2 ? 'before' : 'after'
  }

  clearDragState() {
    if (this.draggedItem) delete this.draggedItem.dataset.suiDragState
    if (this.dragTarget) delete this.dragTarget.dataset.suiDropState
    this.draggedItem = null
    this.dragTarget = null
  }

  handleSwipeEvent(event) {
    if (event.type === 'pointerdown') this.swipeStart(event)
    if (event.type === 'pointermove') this.swipeMove(event)
    if (event.type === 'pointerup') this.swipeEnd(event)
    if (event.type === 'pointercancel') this.swipeCancel(event)
  }

  swipeStart(event) {
    const content = this.role('swipe-content')
    if (!content || (event.target !== this.element && !content.contains(event.target))) return
    if (event.pointerType === 'mouse' && event.button !== 0) return
    if (event.target.closest?.('button, a, input, select, textarea, form')) return
    this.swipePointer = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      currentX: event.clientX,
      currentY: event.clientY
    }
    try {
      this.element.setPointerCapture?.(event.pointerId)
    } catch (_error) {
      // Pointer capture remains optional.
    }
  }

  swipeMove(event) {
    if (!this.swipePointer || event.pointerId !== this.swipePointer.id) return
    this.swipePointer.currentX = event.clientX
    this.swipePointer.currentY = event.clientY
  }

  swipeEnd(event) {
    if (!this.swipePointer || event.pointerId !== this.swipePointer.id) return
    const deltaX = event.clientX - this.swipePointer.x
    const deltaY = event.clientY - this.swipePointer.y
    const rtl = getComputedStyle(this.element).direction === 'rtl'
    const revealsLeading = rtl ? deltaX < 0 : deltaX > 0
    const correctDirection = this.config.edge === 'leading' ? revealsLeading : !revealsLeading
    const threshold = Math.max(0, Number(this.config.threshold || 72))
    if (correctDirection && Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) >= threshold) {
      this.element.dataset.suiSwipeState = 'revealed'
      const status = this.role('swipe-status')
      if (status) status.textContent = `${this.config.label || 'Swipe'} actions available`
    }
    this.releasePointer(event)
    this.swipePointer = null
  }

  swipeCancel(event) {
    this.releasePointer(event)
    this.swipePointer = null
  }

  releasePointer(event) {
    if (this.element.hasPointerCapture?.(event.pointerId)) this.element.releasePointerCapture(event.pointerId)
  }

  handleDocumentEvent(event) {
    if (event.type === 'change' && this.roleForEvent(event, 'file-input')) this.validateFiles(event)
    if (event.type === 'submit' && this.element.contains(event.target)) this.beginUpload(event)
    if (event.type === 'direct-upload:initialize') this.directUploadInitialize(event)
    if (event.type === 'direct-upload:start') this.directUploadStart(event)
    if (event.type === 'direct-upload:progress') this.directUploadProgress(event)
    if (event.type === 'direct-upload:error') this.directUploadError(event)
    if (event.type === 'direct-upload:end') this.directUploadEnd(event)
    if (event.type === 'turbo:submit-start') this.showProgress(null, 'Saving document')
    if (event.type === 'turbo:submit-end') this.turboSubmitEnd(event)
  }

  validateFiles(event = null) {
    const input = event ? this.roleForEvent(event, 'file-input') : this.role('file-input')
    if (!input?.files) return true
    const totalBytes = Array.from(input.files).reduce((total, file) => total + file.size, 0)
    const maxFiles = Math.max(1, Number(this.config.maxFiles || 1))
    const maxBytes = Math.max(0, Number(this.config.maxBytes || 0))
    const validCount = input.files.length <= maxFiles
    const validBytes = maxBytes === 0 || totalBytes <= maxBytes
    const valid = validCount && validBytes
    const message = validCount
      ? `Selected files exceed the ${maxBytes}-byte limit.`
      : `Select no more than ${maxFiles} files.`
    input.setCustomValidity(valid ? '' : message)
    const status = this.role('upload-status')
    if (status) status.textContent = valid
      ? `${input.files.length} file${input.files.length === 1 ? '' : 's'} selected`
      : message
    return valid
  }

  beginUpload(event) {
    if (!this.validateFiles()) {
      event.preventDefault()
      this.role('file-input')?.reportValidity()
      return
    }
    this.showProgress(null, this.config.directUpload ? 'Preparing direct upload' : 'Uploading document')
    const submit = this.role('upload-submit')
    if (submit) submit.disabled = true
  }

  ownsUploadEvent(event) {
    const input = this.role('file-input')
    return !event.target || !input || event.target === input
  }

  directUploadInitialize(event) {
    if (this.ownsUploadEvent(event)) this.showProgress(0, 'Preparing direct upload')
  }

  directUploadStart(event) {
    if (this.ownsUploadEvent(event)) this.showProgress(0, 'Uploading document')
  }

  directUploadProgress(event) {
    if (!this.ownsUploadEvent(event)) return
    const progress = Number(event.detail?.progress)
    this.showProgress(Number.isFinite(progress) ? progress : null, 'Uploading document')
  }

  directUploadError(event) {
    if (!this.ownsUploadEvent(event)) return
    this.showProgress(null, String(event.detail?.error || 'Document upload failed'))
    const submit = this.role('upload-submit')
    if (submit) submit.disabled = false
  }

  directUploadEnd(event) {
    if (this.ownsUploadEvent(event)) this.showProgress(100, 'Direct upload complete; saving document')
  }

  turboSubmitEnd(event) {
    if (event.detail?.success) {
      this.showProgress(100, 'Document saved')
    } else {
      this.showProgress(null, 'Document could not be saved')
      const submit = this.role('upload-submit')
      if (submit) submit.disabled = false
    }
  }

  showProgress(value, message) {
    const progress = this.role('upload-progress')
    if (progress) {
      progress.hidden = false
      if (value === null) progress.removeAttribute('value')
      else progress.value = Math.max(0, Math.min(100, value))
    }
    const status = this.role('upload-status')
    if (status) status.textContent = message
  }
}

class AsyncImageBehavior {
  constructor(element) {
    this.element = element
  }

  connect() {
    this.element.dataset.suiAsyncImageEnhanced = 'true'
    this.showPhase('loading')
    const image = this.role('image')
    if (image?.complete) image.naturalWidth > 0 ? this.showPhase('success') : this.showPhase('failure')
  }

  disconnect() {
    delete this.element.dataset.suiAsyncImageEnhanced
    delete this.element.dataset.suiAsyncImagePhase
    this.element.removeAttribute('aria-busy')
    const loading = this.role('loading')
    const image = this.role('image')
    const failure = this.role('failure')
    if (loading) loading.hidden = true
    if (image) image.hidden = false
    if (failure) failure.hidden = true
  }

  handleEvent(event) {
    const image = this.role('image')
    if (event.target !== image) return
    if (event.type === 'load') this.showPhase('success')
    if (event.type === 'error') this.showPhase('failure')
  }

  role(name) {
    return this.element.querySelector(`[data-sui-async-image-role="${name}"]`)
  }

  showPhase(phase) {
    if (!['loading', 'success', 'failure'].includes(phase)) return
    this.element.dataset.suiAsyncImagePhase = phase
    this.element.setAttribute('aria-busy', phase === 'loading' ? 'true' : 'false')
    const loading = this.role('loading')
    const image = this.role('image')
    const failure = this.role('failure')
    if (loading) loading.hidden = phase !== 'loading'
    if (image) image.hidden = phase === 'failure'
    if (failure) failure.hidden = phase !== 'failure'
    dispatchSemantic(this.element, 'swift-ui-async-image:phase-change', { phase })
  }
}

class CanvasBehavior {
  constructor(element) {
    this.element = element
  }

  connect() {
    this.draw()
  }

  update() {
    this.draw()
  }

  config() {
    return readJSONAttribute(this.element, 'data-sui-canvas', {}, 512 * 1024) || {}
  }

  draw() {
    const surface = this.element.querySelector('[data-sui-canvas-role="surface"]')
    if (!(surface instanceof HTMLCanvasElement)) return
    const config = this.config()
    const width = Math.min(8192, Math.max(1, Number(config.width || 1)))
    const height = Math.min(8192, Math.max(1, Number(config.height || 1)))
    const commands = Array.isArray(config.commands) ? config.commands.slice(0, 2048) : []
    const context = surface.getContext('2d')
    if (!context) return
    const ratio = Math.min(4, Math.max(1, window.devicePixelRatio || 1))
    surface.width = Math.round(width * ratio)
    surface.height = Math.round(height * ratio)
    surface.style.aspectRatio = `${width} / ${height}`
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    commands.forEach((command) => this.drawCommand(context, command, width, height))
    this.element.dataset.suiCanvasReady = 'true'
    dispatchSemantic(this.element, 'swift-ui-canvas:ready', { commandCount: commands.length })
  }

  drawCommand(context, command, width, height) {
    if (!command || typeof command !== 'object' || Array.isArray(command)) return
    switch (command.type) {
      case 'clear':
        context.clearRect(0, 0, width, height)
        if (command.color !== 'transparent') {
          context.fillStyle = command.color
          context.fillRect(0, 0, width, height)
        }
        break
      case 'fill_rect':
        context.fillStyle = command.color
        context.fillRect(command.x, command.y, command.width, command.height)
        break
      case 'stroke_rect':
        context.strokeStyle = command.color
        context.lineWidth = command.line_width
        context.strokeRect(command.x, command.y, command.width, command.height)
        break
      case 'line':
        context.beginPath()
        context.moveTo(command.x1, command.y1)
        context.lineTo(command.x2, command.y2)
        context.strokeStyle = command.color
        context.lineWidth = command.line_width
        context.stroke()
        break
      case 'circle':
        context.beginPath()
        context.arc(command.x, command.y, command.radius, 0, Math.PI * 2)
        context.lineWidth = command.line_width
        if (command.fill) {
          context.fillStyle = command.color
          context.fill()
        } else {
          context.strokeStyle = command.color
          context.stroke()
        }
        break
      case 'text':
        context.fillStyle = command.color
        context.font = `${command.size}px ui-sans-serif, system-ui, sans-serif`
        context.textAlign = command.align
        context.fillText(command.text, command.x, command.y)
        break
    }
  }
}

export const SwiftUIRails = new SwiftUIRuntime()

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => SwiftUIRails.start(), { once: true })
} else {
  SwiftUIRails.start()
}

window.SwiftUIRails = SwiftUIRails
