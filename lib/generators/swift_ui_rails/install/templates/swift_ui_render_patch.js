export const RENDER_PATCH_VERSION = 1

const KEY_ATTRIBUTE = "data-swift-ui-ir-key"
const KEY_PATTERN = /^sui-[0-9a-f]{24}$/
const ATTRIBUTE_PATTERN = /^[A-Za-z_:][A-Za-z0-9_.:-]{0,127}$/
const FORBIDDEN_FRAGMENT_TAGS = new Set(["base", "embed", "link", "meta", "object", "script", "style"])
const FORBIDDEN_FRAGMENT_ATTRIBUTES = new Set(["srcdoc", "srcset"])
const URL_ATTRIBUTES = new Set(["action", "cite", "formaction", "href", "poster", "src", "xlink:href"])
const ALLOWED_IFRAME_SANDBOX_TOKENS = new Set([
  "allow-downloads", "allow-forms", "allow-modals", "allow-orientation-lock",
  "allow-pointer-lock", "allow-popups", "allow-popups-to-escape-sandbox",
  "allow-presentation", "allow-same-origin", "allow-scripts",
  "allow-storage-access-by-user-activation", "allow-top-navigation",
  "allow-top-navigation-by-user-activation"
])
const ASCII_CONTROL_OR_SPACE_PATTERN = /[\u0000-\u0020\u007f]/
const MAX_OPERATIONS = 512
const MAX_ATTRIBUTES_PER_OPERATION = 128
const MAX_ATTRIBUTE_VALUE_BYTES = 64 * 1024
const MAX_TEXT_BYTES = 256 * 1024
const MAX_FRAGMENT_BYTES = 1024 * 1024
const MAX_PATCH_HTML_BYTES = 2 * 1024 * 1024

function byteLength(value) {
  return new TextEncoder().encode(value).byteLength
}

function isRecord(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false
  const prototype = Object.getPrototypeOf(value)
  return prototype === Object.prototype || prototype === null
}

export class RenderPatchError extends Error {
  constructor(code, message, { operationIndex = null, cause = null } = {}) {
    super(message, cause ? { cause } : undefined)
    this.name = "RenderPatchError"
    this.code = code
    this.operationIndex = operationIndex
  }
}

export function isRenderPatchError(error) {
  return error instanceof RenderPatchError
}

function fail(code, message, operationIndex = null, cause = null) {
  throw new RenderPatchError(code, message, { operationIndex, cause })
}

function validKey(value, field, operationIndex) {
  if (typeof value !== "string" || !KEY_PATTERN.test(value)) {
    fail("invalid_key", `Render patch ${field} must match ${KEY_PATTERN}.`, operationIndex)
  }
  return value
}

function optionalKey(value, field, operationIndex) {
  return value === undefined || value === null ? null : validKey(value, field, operationIndex)
}

function operationKey(operation, operationIndex) {
  return validKey(
    operation.key ?? operation.target_key ?? operation.target,
    "key",
    operationIndex
  )
}

function parentKey(operation, operationIndex) {
  return validKey(
    operation.parent_key ?? operation.parent,
    "parent_key",
    operationIndex
  )
}

function beforeKey(operation, operationIndex) {
  return optionalKey(
    operation.before_key ?? operation.before,
    "before_key",
    operationIndex
  )
}

function normalizedOperationName(operation, operationIndex) {
  const name = operation.op ?? operation.type
  const aliases = {
    set_attributes: "attributes",
    set_text: "text",
    insert_before: "insert",
    move_before: "move"
  }
  const normalized = aliases[name] || name
  if (!["attributes", "text", "remove", "insert", "move", "replace"].includes(normalized)) {
    fail("unsupported_operation", `Unsupported render patch operation: ${String(name)}`, operationIndex)
  }
  return normalized
}

function normalizedAttributeValue(value, name, operationIndex) {
  if (value === null || value === false) return null
  if (!["string", "number", "boolean"].includes(typeof value)) {
    fail("invalid_attribute_value", `Attribute ${name} has an unsupported value.`, operationIndex)
  }

  const normalized = value === true ? "" : String(value)
  if (byteLength(normalized) > MAX_ATTRIBUTE_VALUE_BYTES) {
    fail("attribute_value_too_large", `Attribute ${name} exceeds the patch limit.`, operationIndex)
  }
  return normalized
}

function validateAttributeName(name, operationIndex) {
  if (typeof name !== "string" || !ATTRIBUTE_PATTERN.test(name)) {
    fail("invalid_attribute_name", "Render patch attribute name is invalid.", operationIndex)
  }
  const normalized = name.toLowerCase()
  if (normalized === KEY_ATTRIBUTE || normalized.startsWith("on") || FORBIDDEN_FRAGMENT_ATTRIBUTES.has(normalized)) {
    fail("protected_attribute", `Render patch cannot mutate ${name}.`, operationIndex)
  }
  return name
}

function validateUrlAttribute(tagName, name, value, operationIndex) {
  const normalizedName = name.toLowerCase()
  if (!URL_ATTRIBUTES.has(normalizedName)) return

  const normalizedValue = String(value).trim()
  if (!normalizedValue || ASCII_CONTROL_OR_SPACE_PATTERN.test(normalizedValue)) {
    fail("unsafe_url", `Render patch ${normalizedName} URL is invalid.`, operationIndex)
  }

  const scheme = normalizedValue.match(/^([a-z][a-z0-9+.-]*):/i)?.[1]?.toLowerCase()
  if (!scheme || scheme === "http" || scheme === "https") return
  if (tagName === "iframe" && normalizedName === "src" && normalizedValue.toLowerCase() === "about:blank") return

  fail("unsafe_url", `Render patch ${normalizedName} URL uses an unsafe scheme.`, operationIndex)
}

function validateIframeAttributes(attributes, operationIndex) {
  const title = attributes.get("title")
  const source = attributes.get("src")
  if (typeof title !== "string" || !title.trim() || typeof source !== "string" || !source) {
    fail("unsafe_iframe", "Render patch iframe requires a title and source.", operationIndex)
  }
  if (!attributes.has("sandbox")) {
    fail("unsafe_iframe", "Render patch iframe requires a sandbox.", operationIndex)
  }

  const tokens = String(attributes.get("sandbox")).split(/\s+/).filter(Boolean)
  if (tokens.some((token) => !ALLOWED_IFRAME_SANDBOX_TOKENS.has(token)) ||
      (tokens.includes("allow-scripts") && tokens.includes("allow-same-origin"))) {
    fail("unsafe_iframe", "Render patch iframe sandbox is unsafe.", operationIndex)
  }
}

function fragmentElements(element) {
  const elements = []
  const visit = (candidate) => {
    elements.push(candidate)
    Array.from(candidate.children).forEach(visit)
    if (candidate instanceof HTMLTemplateElement) Array.from(candidate.content.children).forEach(visit)
  }
  visit(element)
  return elements
}

function validateFragmentElement(candidate, operationIndex) {
  const tagName = candidate.localName.toLowerCase()
  if (FORBIDDEN_FRAGMENT_TAGS.has(tagName)) {
    fail("active_fragment", `Render patch cannot insert a ${tagName} element.`, operationIndex)
  }

  const key = candidate.getAttribute(KEY_ATTRIBUTE)
  if (!key) fail("missing_fragment_key", "Every render patch fragment element requires a key.", operationIndex)
  validKey(key, KEY_ATTRIBUTE, operationIndex)

  const attributes = new Map()
  for (const attribute of candidate.attributes) {
    const name = attribute.name.toLowerCase()
    if (name !== KEY_ATTRIBUTE && (name.startsWith("on") || FORBIDDEN_FRAGMENT_ATTRIBUTES.has(name))) {
      fail("active_fragment", `Render patch fragment attribute ${name} is forbidden.`, operationIndex)
    }
    validateUrlAttribute(tagName, name, attribute.value, operationIndex)
    attributes.set(name, attribute.value)
  }
  if (tagName === "iframe") validateIframeAttributes(attributes, operationIndex)
  return key
}

function prepareAttributes(operation, operationIndex) {
  const set = new Map()
  const remove = new Set()
  const attributes = operation.attributes
  const synchronize = attributes !== undefined

  if (attributes !== undefined) {
    if (!isRecord(attributes)) fail("invalid_attributes", "Patch attributes must be an object.", operationIndex)
    for (const [rawName, value] of Object.entries(attributes)) {
      const name = validateAttributeName(rawName, operationIndex)
      const normalized = normalizedAttributeValue(value, name, operationIndex)
      if (normalized === null) remove.add(name)
      else set.set(name, normalized)
    }
  }

  if (operation.set !== undefined) {
    if (!isRecord(operation.set)) fail("invalid_attributes", "Patch set must be an object.", operationIndex)
    for (const [rawName, value] of Object.entries(operation.set)) {
      const name = validateAttributeName(rawName, operationIndex)
      const normalized = normalizedAttributeValue(value, name, operationIndex)
      if (normalized === null) remove.add(name)
      else set.set(name, normalized)
    }
  }

  if (operation.remove !== undefined) {
    if (!Array.isArray(operation.remove)) fail("invalid_attributes", "Patch remove must be an array.", operationIndex)
    for (const rawName of operation.remove) remove.add(validateAttributeName(rawName, operationIndex))
  }

  if (set.size + remove.size > MAX_ATTRIBUTES_PER_OPERATION) {
    fail("too_many_attributes", "Render patch attribute operation is too large.", operationIndex)
  }
  for (const name of set.keys()) remove.delete(name)

  return { set, remove, synchronize }
}

function prepareFragment(html, operationIndex) {
  if (typeof html !== "string") fail("invalid_html", "Patch fragment must be a string.", operationIndex)
  const bytes = byteLength(html)
  if (bytes > MAX_FRAGMENT_BYTES) fail("fragment_too_large", "Patch fragment exceeds 1 MB.", operationIndex)
  if (/<\s*script(?:\s|>)/i.test(html)) fail("active_fragment", "Patch fragments cannot contain scripts.", operationIndex)

  return { bytes, html }
}

function parseFragment(fragment, context, operationIndex) {
  const range = document.createRange()
  range.selectNodeContents(context)
  const contents = range.createContextualFragment(fragment.html.trim())
  const meaningfulNodes = Array.from(contents.childNodes).filter((node) => {
    return node.nodeType !== Node.TEXT_NODE || node.textContent.trim() !== ""
  })
  if (meaningfulNodes.length !== 1 || !(meaningfulNodes[0] instanceof Element)) {
    fail("invalid_fragment", "Patch fragment must contain exactly one element.", operationIndex)
  }

  const element = meaningfulNodes[0]
  if (element.matches("script") || element.querySelector("script")) {
    fail("active_fragment", "Patch fragments cannot contain scripts.", operationIndex)
  }

  const keys = new Set()
  for (const candidate of fragmentElements(element)) {
    const key = validateFragmentElement(candidate, operationIndex)
    if (keys.has(key)) fail("duplicate_fragment_key", `Patch fragment repeats key ${key}.`, operationIndex)
    keys.add(key)
  }
  return element
}

function prepareOperation(operation, operationIndex) {
  if (!isRecord(operation)) fail("invalid_operation", "Each patch operation must be an object.", operationIndex)
  const op = normalizedOperationName(operation, operationIndex)

  switch (op) {
    case "attributes":
      return { op, key: operationKey(operation, operationIndex), ...prepareAttributes(operation, operationIndex) }
    case "text": { // eslint-disable-line no-case-declarations
      const value = operation.value ?? operation.text
      if (typeof value !== "string") fail("invalid_text", "Patch text must be a string.", operationIndex)
      if (byteLength(value) > MAX_TEXT_BYTES) fail("text_too_large", "Patch text exceeds the limit.", operationIndex)
      return { op, key: operationKey(operation, operationIndex), value }
    }
    case "remove":
      return { op, key: operationKey(operation, operationIndex) }
    case "move":
      return {
        op,
        key: operationKey(operation, operationIndex),
        parentKey: parentKey(operation, operationIndex),
        beforeKey: beforeKey(operation, operationIndex)
      }
    case "insert":
    case "replace": { // eslint-disable-line no-case-declarations
      const fragment = prepareFragment(operation.html, operationIndex)
      return {
        op,
        key: op === "replace" ? operationKey(operation, operationIndex) : null,
        parentKey: op === "insert" ? parentKey(operation, operationIndex) : null,
        beforeKey: op === "insert" ? beforeKey(operation, operationIndex) : null,
        fragment
      }
    }
    default:
      fail("unsupported_operation", `Unsupported render patch operation: ${op}`, operationIndex)
  }
}

function preparePatch(root, patch) {
  if (!(root instanceof HTMLElement)) fail("invalid_root", "Render patch root must be an HTML element.")
  if (!isRecord(patch)) fail("invalid_patch", "Render patch must be an object.")
  if (patch.version !== RENDER_PATCH_VERSION) {
    fail("unsupported_version", `Render patch version ${String(patch.version)} is not supported.`)
  }

  const componentId = patch.component_id
  if (componentId !== undefined && componentId !== root.id) {
    fail("component_mismatch", "Render patch targets a different component.")
  }

  if (patch.operations !== undefined && patch.ops !== undefined) {
    fail("ambiguous_operations", "Render patch cannot contain both operations and ops.")
  }
  const operations = patch.operations ?? patch.ops
  if (!Array.isArray(operations)) fail("invalid_operations", "Render patch operations must be an array.")
  if (operations.length > MAX_OPERATIONS) fail("too_many_operations", "Render patch has too many operations.")

  let htmlBytes = 0
  const prepared = operations.map((operation, index) => {
    const result = prepareOperation(operation, index)
    htmlBytes += result.fragment?.bytes || 0
    if (htmlBytes > MAX_PATCH_HTML_BYTES) fail("patch_too_large", "Render patch HTML exceeds 2 MB.", index)
    return result
  })

  return { operations: prepared, revision: patch.revision ?? null }
}

function buildKeyIndex(root) {
  const index = new Map()
  const candidates = [root, ...root.querySelectorAll(`[${KEY_ATTRIBUTE}]`)]
  for (const candidate of candidates) {
    if (!candidate.hasAttribute(KEY_ATTRIBUTE)) continue
    const key = validKey(candidate.getAttribute(KEY_ATTRIBUTE), KEY_ATTRIBUTE, null)
    if (index.has(key)) fail("duplicate_dom_key", `Rendered DOM repeats key ${key}.`)
    index.set(key, candidate)
  }
  return index
}

function targetFor(index, key, operationIndex) {
  const target = index.get(key)
  if (!(target instanceof Element) || !target.isConnected) {
    fail("missing_target", `Render patch target ${key} is missing.`, operationIndex)
  }
  return target
}

function subtreeKeys(element) {
  return fragmentElements(element)
    .filter((candidate) => candidate.hasAttribute(KEY_ATTRIBUTE))
    .map((candidate) => candidate.getAttribute(KEY_ATTRIBUTE))
}

function deleteSubtreeFromIndex(element, index) {
  subtreeKeys(element).forEach((key) => index.delete(key))
}

function addSubtreeToIndex(element, index, operationIndex, permittedKeys = new Set()) {
  const candidates = fragmentElements(element)
  for (const candidate of candidates) {
    const key = validKey(candidate.getAttribute(KEY_ATTRIBUTE), KEY_ATTRIBUTE, operationIndex)
    if (index.has(key) && !permittedKeys.has(key)) {
      fail("duplicate_dom_key", `Patch would duplicate key ${key}.`, operationIndex)
    }
    index.set(key, candidate)
  }
}

function synchronizeLiveAttribute(element, name, value) {
  const normalizedName = name.toLowerCase()
  if (normalizedName === "value" && "value" in element && element.type !== "file") element.value = value
  if (["checked", "selected", "disabled"].includes(normalizedName) && normalizedName in element) {
    element[normalizedName] = value !== null
  }
}

function volatileAttribute(name) {
  return [
    "data-swift-ui-reactive-patch-token-value",
    "data-swift-ui-reactive-baseline-token-value",
    "data-swift-ui-reactive-render-revision-value"
  ].includes(name) || (name.startsWith("data-swift-ui-reactive-") && name.includes("token"))
}

function projectedAttributes(target, operation) {
  const attributes = new Map(Array.from(target.attributes, ({ name, value }) => [name.toLowerCase(), value]))
  if (operation.synchronize) {
    for (const name of attributes.keys()) {
      if (name === KEY_ATTRIBUTE || volatileAttribute(name) || operation.set.has(name)) continue
      attributes.delete(name)
    }
  }
  for (const name of operation.remove) attributes.delete(name.toLowerCase())
  for (const [name, value] of operation.set) attributes.set(name.toLowerCase(), value)
  return attributes
}

function applyAttributes(target, operation, operationIndex) {
  const tagName = target.localName.toLowerCase()
  for (const [name, value] of operation.set) validateUrlAttribute(tagName, name, value, operationIndex)
  const finalAttributes = projectedAttributes(target, operation)
  if (tagName === "iframe") validateIframeAttributes(finalAttributes, operationIndex)

  if (operation.synchronize) {
    Array.from(target.attributes).forEach(({ name }) => {
      if (name === KEY_ATTRIBUTE || volatileAttribute(name) || operation.set.has(name)) return
      target.removeAttribute(name)
      synchronizeLiveAttribute(target, name, null)
    })
  }
  for (const name of operation.remove) {
    target.removeAttribute(name)
    synchronizeLiveAttribute(target, name, null)
  }
  for (const [name, value] of operation.set) {
    target.setAttribute(name, value)
    synchronizeLiveAttribute(target, name, value)
  }
}

function directBeforeTarget(index, parent, beforeKeyValue, operationIndex) {
  if (!beforeKeyValue) return null
  const before = targetFor(index, beforeKeyValue, operationIndex)
  if (before.parentElement !== parent) {
    fail("invalid_sibling", `Patch before target ${beforeKeyValue} is not a direct child.`, operationIndex)
  }
  return before
}

function locatorFor(element, root) {
  if (!(element instanceof HTMLElement) || !root.contains(element)) return null
  const key = element.getAttribute(KEY_ATTRIBUTE)
  if (key && KEY_PATTERN.test(key)) return { type: "key", value: key }
  if (element.id) return { type: "id", value: element.id }
  if (element.dataset.binding) return { type: "binding", value: element.dataset.binding }
  return null
}

function findByLocator(root, locator, index) {
  if (!locator) return null
  if (locator.type === "key") return index.get(locator.value) || null
  const attribute = locator.type === "id" ? "id" : "data-binding"
  return [root, ...root.querySelectorAll(`[${attribute}]`)].find((element) => {
    return element.getAttribute(attribute) === locator.value
  }) || null
}

function controlState(element, root, focus = false) {
  const locator = locatorFor(element, root)
  if (!locator) return null
  const state = { locator, focus, element }
  if (element instanceof HTMLInputElement) {
    if (element.type !== "file") state.value = element.value
    if (["checkbox", "radio"].includes(element.type)) state.checked = element.checked
  } else if (element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement) {
    state.value = element.value
  }
  if (focus && typeof element.selectionStart === "number") {
    state.selectionStart = element.selectionStart
    state.selectionEnd = element.selectionEnd
    state.selectionDirection = element.selectionDirection
  }
  return state
}

function captureBrowserState(root, focusTarget, preserveBindingNames) {
  const active = focusTarget instanceof HTMLElement && root.contains(focusTarget)
    ? focusTarget
    : (document.activeElement instanceof HTMLElement && root.contains(document.activeElement) ? document.activeElement : null)
  const states = []
  const seen = new Set()
  if (active) {
    const state = controlState(active, root, true)
    if (state) {
      states.push(state)
      seen.add(active)
    }
  }

  const bindings = new Set(Array.from(preserveBindingNames || [], String))
  if (bindings.size > 0) {
    root.querySelectorAll("[data-binding]").forEach((element) => {
      if (!bindings.has(element.dataset.binding) || seen.has(element)) return
      const state = controlState(element, root)
      if (state) states.push(state)
    })
  }
  return states
}

function restoreBrowserState(root, states, index) {
  for (const state of states) {
    const element = state.element.isConnected && root.contains(state.element)
      ? state.element
      : findByLocator(root, state.locator, index)
    if (!(element instanceof HTMLElement)) continue

    if (state.value !== undefined && "value" in element && element.type !== "file") element.value = state.value
    if (state.checked !== undefined && "checked" in element) element.checked = state.checked
    if (!state.focus) continue

    try {
      element.focus({ preventScroll: true })
    } catch (_error) {
      element.focus()
    }
    if (state.selectionStart !== undefined && typeof element.setSelectionRange === "function") {
      try {
        element.setSelectionRange(state.selectionStart, state.selectionEnd, state.selectionDirection)
      } catch (_selectionError) {
        // Some input types expose selectionStart but reject setSelectionRange.
      }
    }
  }
}

function dispatchPatchEvent(root, name, detail, cancelable = false) {
  return root.dispatchEvent(new CustomEvent(name, {
    bubbles: true,
    cancelable,
    detail
  }))
}

function publicError(error) {
  return {
    name: error.name,
    code: error.code || "apply_failed",
    message: error.message,
    operationIndex: error.operationIndex
  }
}

export function applyRenderPatch(root, patch, options = {}) {
  const startedAt = performance.now()
  try {
    const prepared = preparePatch(root, patch)
    const index = buildKeyIndex(root)
    const browserState = captureBrowserState(root, options.focusTarget, options.preserveBindingNames)
    dispatchPatchEvent(root, "swift-ui-render-patch:before", {
      version: RENDER_PATCH_VERSION,
      operationCount: prepared.operations.length
    })

    prepared.operations.forEach((operation, operationIndex) => {
      if (operation.op === "attributes") {
        applyAttributes(targetFor(index, operation.key, operationIndex), operation, operationIndex)
      } else if (operation.op === "text") {
        const target = targetFor(index, operation.key, operationIndex)
        Array.from(target.children).forEach((child) => deleteSubtreeFromIndex(child, index))
        target.textContent = operation.value
      } else if (operation.op === "remove") {
        const target = targetFor(index, operation.key, operationIndex)
        if (target === root) fail("root_mutation", "Render patch cannot remove its component root.", operationIndex)
        deleteSubtreeFromIndex(target, index)
        target.remove()
      } else if (operation.op === "insert") {
        const parent = targetFor(index, operation.parentKey, operationIndex)
        const before = directBeforeTarget(index, parent, operation.beforeKey, operationIndex)
        const inserted = parseFragment(operation.fragment, parent, operationIndex)
        addSubtreeToIndex(inserted, index, operationIndex)
        parent.insertBefore(inserted, before)
      } else if (operation.op === "move") {
        const target = targetFor(index, operation.key, operationIndex)
        const parent = targetFor(index, operation.parentKey, operationIndex)
        const before = directBeforeTarget(index, parent, operation.beforeKey, operationIndex)
        if (target === root || target.contains(parent)) {
          fail("invalid_move", "Render patch move would create an invalid tree.", operationIndex)
        }
        parent.insertBefore(target, before)
      } else if (operation.op === "replace") {
        const target = targetFor(index, operation.key, operationIndex)
        if (target === root) fail("root_mutation", "Render patch cannot replace its component root.", operationIndex)
        const replacement = parseFragment(operation.fragment, target.parentElement, operationIndex)
        if (replacement.getAttribute(KEY_ATTRIBUTE) !== operation.key) {
          fail("replacement_key_mismatch", "Replacement fragment must retain its target key.", operationIndex)
        }
        const replacedKeys = new Set(subtreeKeys(target))
        deleteSubtreeFromIndex(target, index)
        addSubtreeToIndex(replacement, index, operationIndex, replacedKeys)
        target.replaceWith(replacement)
      }
    })

    const finalIndex = buildKeyIndex(root)
    restoreBrowserState(root, browserState, finalIndex)
    if (prepared.revision !== null) root.dataset.swiftUiRenderRevision = String(prepared.revision)
    root.dataset.swiftUiRenderMode = "patch"
    root.dataset.swiftUiPatchOperations = String(prepared.operations.length)
    const result = {
      applied: true,
      operationCount: prepared.operations.length,
      duration: performance.now() - startedAt
    }
    dispatchPatchEvent(root, "swift-ui-render-patch:after", {
      version: RENDER_PATCH_VERSION,
      ...result
    })
    return result
  } catch (cause) {
    const error = cause instanceof RenderPatchError
      ? cause
      : new RenderPatchError("apply_failed", "Render patch could not be applied.", { cause })
    const notPrevented = root instanceof EventTarget
      ? dispatchPatchEvent(root, "swift-ui-render-patch:error", {
        version: RENDER_PATCH_VERSION,
        error: publicError(error)
      }, true)
      : true
    error.defaultPrevented = !notPrevented
    throw error
  }
}
