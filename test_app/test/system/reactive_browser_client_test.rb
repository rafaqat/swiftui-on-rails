# frozen_string_literal: true

require "application_system_test_case"

class ReactiveBrowserClientTest < ApplicationSystemTestCase
  test "enhances semantic interaction presentation workflow image and canvas descriptors" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      document.addEventListener('swift-ui-key-press', (event) => {
        document.body.dataset.suiObservedKey = event.detail.key
      })
      document.body.insertAdjacentHTML('beforeend', `
        <button id="semantic-key" type="button"
                data-sui-keypress='{"keys":["k"],"modifiers":[],"phase":"keydown","scope":"element","preventDefault":true}'>Key</button>
        <div id="semantic-tabs" data-sui-tabs='{"selection":"first","initialSelection":"first"}'>
          <div role="tablist">
            <a id="tab-first" role="tab" href="#panel-first" aria-controls="panel-first"
               aria-selected="true" data-sui-tab='{"value":"first","local":true}'>First</a>
            <a id="tab-second" role="tab" href="#panel-second" aria-controls="panel-second"
               aria-selected="false" data-sui-tab='{"value":"second","local":true}'>Second</a>
          </div>
          <section id="panel-first" data-sui-tab-panel='{"value":"first","selected":true}'>One</section>
          <section id="panel-second" data-sui-tab-panel='{"value":"second","selected":false}'>Two</section>
        </div>
        <button id="semantic-present" type="button" data-sui-present="semantic-dialog">Open</button>
        <dialog id="semantic-dialog" data-sui-dialog='{"kind":"sheet","presented":false,"dismissible":true}'>Dialog</dialog>
        <div id="semantic-swipe" data-sui-workflow='{"kind":"swipe","edge":"trailing","threshold":20,"label":"Delete"}'>
          <div data-sui-workflow-role="swipe-content">Swipe me</div>
          <span data-sui-workflow-role="swipe-status"></span>
          <div data-sui-workflow-role="swipe-buttons"><button type="button">Delete</button></div>
        </div>
        <div id="semantic-image" data-sui-async-image='{"cache":"browser"}'>
          <span data-sui-async-image-role="loading">Loading</span>
          <img data-sui-async-image-role="image" alt="Probe">
          <span data-sui-async-image-role="failure">Failed</span>
        </div>
        <div id="semantic-canvas"
             data-sui-canvas='{"width":40,"height":20,"commands":[{"type":"fill_rect","x":0,"y":0,"width":10,"height":10,"color":"#000000"}]}'>
          <canvas data-sui-canvas-role="surface"></canvas>
        </div>
      `)
    JAVASCRIPT

    assert_selector "#semantic-tabs[data-sui-enhanced='tabs']"
    assert_selector "#semantic-canvas[data-sui-canvas-ready='true']"
    assert_selector "#semantic-image[data-sui-async-image-enhanced='true']"

    find("#tab-second").click
    assert_selector "#tab-second[aria-selected='true']"
    assert_selector "#panel-first[hidden]", visible: :all
    assert_no_selector "#panel-second[hidden]", visible: :all

    find("#semantic-present").click
    assert_selector "#semantic-dialog[open]"

    page.execute_script <<~JAVASCRIPT
      document.querySelector('#semantic-key').dispatchEvent(
        new KeyboardEvent('keydown', { key: 'k', bubbles: true, cancelable: true })
      )
      document.querySelector('#semantic-image img').dispatchEvent(new Event('load', { bubbles: true }))
      const swipe = document.querySelector('#semantic-swipe [data-sui-workflow-role="swipe-content"]')
      swipe.dispatchEvent(new PointerEvent('pointerdown', {
        pointerId: 7, pointerType: 'touch', clientX: 100, clientY: 10, bubbles: true, isPrimary: true
      }))
      swipe.dispatchEvent(new PointerEvent('pointerup', {
        pointerId: 7, pointerType: 'touch', clientX: 60, clientY: 10, bubbles: true, isPrimary: true
      }))
    JAVASCRIPT

    assert_selector "body[data-sui-observed-key='k']"
    assert_selector "#semantic-image[data-sui-async-image-phase='success'][aria-busy='false']"
    assert_selector "#semantic-swipe[data-sui-swipe-state='revealed']"
    assert_selector "#semantic-swipe [data-sui-workflow-role='swipe-status']", text: "Delete actions available"
  end

  test "signed semantic actions own conflicting defaults while unsigned markup keeps native fallback" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      window.__semanticActionOriginalFetch = window.fetch
      window.__semanticActionRequests = []
      window.fetch = (url, options = {}) => {
        if (!String(url).includes('/swift_ui/actions')) {
          return window.__semanticActionOriginalFetch(url, options)
        }
        window.__semanticActionRequests.push(JSON.parse(options.body))
        document.body.dataset.semanticActionRequestCount = String(window.__semanticActionRequests.length)
        return Promise.resolve(new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' }
        }))
      }

      document.body.insertAdjacentHTML('beforeend', `
        <div id="signed-link-root" data-sui-root="1" data-sui-id="signed-link-root"
             data-sui-component="ReactiveCounterComponent" data-sui-stream="signed-stream"
             data-sui-snapshot="signed-snapshot">
          <a id="signed-action-link" href="#must-not-navigate"
             data-sui-actions='{"click":"link-action"}'>Signed link</a>
        </div>
        <div id="signed-form-root" data-sui-root="1" data-sui-id="signed-form-root"
             data-sui-component="ReactiveCounterComponent" data-sui-stream="signed-stream"
             data-sui-snapshot="signed-snapshot">
          <form id="signed-action-form" action="/must-not-submit" method="post"
                data-sui-actions='{"submit":"submit-action"}'>
            <button type="submit">Signed submit</button>
          </form>
        </div>
        <div id="signed-focus-root" data-sui-root="1" data-sui-id="signed-focus-root"
             data-sui-component="ReactiveCounterComponent" data-sui-stream="signed-stream"
             data-sui-snapshot="signed-snapshot">
          <input id="signed-focus-input"
                 data-sui-actions='{"focusin":"focus-action","focusout":"blur-action"}'>
        </div>
        <div id="unsigned-link-root" data-sui-root="1" data-sui-id="unsigned-link-root"
             data-sui-component="ReactiveCounterComponent">
          <a id="unsigned-action-link" href="#native-fallback" data-turbo="false"
             data-sui-actions='{"click":"unsigned-action"}'>Unsigned link</a>
        </div>
      `)

      const signedClick = new MouseEvent('click', { bubbles: true, cancelable: true })
      document.querySelector('#signed-action-link').dispatchEvent(signedClick)
      const signedSubmit = new SubmitEvent('submit', { bubbles: true, cancelable: true })
      document.querySelector('#signed-action-form').dispatchEvent(signedSubmit)
      const focusInput = document.querySelector('#signed-focus-input')
      focusInput.dispatchEvent(new FocusEvent('focusin', { bubbles: true, cancelable: false }))
      focusInput.dispatchEvent(new FocusEvent('focusout', { bubbles: true, cancelable: false }))
      const unsignedClick = new MouseEvent('click', { bubbles: true, cancelable: true })
      document.querySelector('#unsigned-action-link').dispatchEvent(unsignedClick)

      document.body.dataset.signedClickPrevented = String(signedClick.defaultPrevented)
      document.body.dataset.signedSubmitPrevented = String(signedSubmit.defaultPrevented)
      document.body.dataset.unsignedClickPrevented = String(unsignedClick.defaultPrevented)
    JAVASCRIPT

    assert_selector "body[data-signed-click-prevented='true'][data-signed-submit-prevented='true']"
    assert_selector "body[data-unsigned-click-prevented='false']"
    assert_equal "#native-fallback", page.evaluate_script("window.location.hash")
    assert_selector "body[data-semantic-action-request-count='4']"
    assert_equal %w[click submit focusin focusout], page.evaluate_script(
      "window.__semanticActionRequests.map((request) => request.event_type)"
    )
  ensure
    if page&.html
      page.execute_script <<~JAVASCRIPT
        if (window.__semanticActionOriginalFetch) window.fetch = window.__semanticActionOriginalFetch
      JAVASCRIPT
    end
  end

  test "serializes updates renews capabilities and applies nested-target JSON actions" do
    visit root_path

    page.execute_script <<~JAVASCRIPT
      window.__swiftUIClientRequests = []
      window.__swiftUIOriginalFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const path = String(url)
        if (!path.includes('/client-probe/') && !path.includes('/swift_ui/actions')) {
          return window.__swiftUIOriginalFetch(url, options)
        }

        return new Promise((resolve) => {
          window.__swiftUIClientRequests.push({ path, options, resolve })
          document.body.dataset.swiftUiClientRequestCount = String(window.__swiftUIClientRequests.length)
        })
      }
    JAVASCRIPT

    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", component_markup)

    wait_until do
      page.evaluate_script(<<~JAVASCRIPT)
        Boolean(document.querySelector('#swift-ui-client-probe-123')._swiftUITransport) &&
          document.querySelector('#swift-ui-client-probe-123')._swiftUITransport.consumer ===
            document.querySelector('#swift-ui-client-probe-456')._swiftUITransport.consumer
      JAVASCRIPT
    end

    page.execute_script <<~JAVASCRIPT
      const input = document.querySelector('#client-probe-step')
      input.value = '2'
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='1']"

    page.execute_script <<~JAVASCRIPT
      const input = document.querySelector('#client-probe-step')
      input.value = '3'
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    sleep 0.15
    assert_selector "body[data-swift-ui-client-request-count='1']"

    resolve_request(0, update_payload("snapshot-renewed-1", "stream-renewed-1", "First response", 2))
    assert_selector "body[data-swift-ui-client-request-count='2']"

    second_request = JSON.parse(page.evaluate_script("window.__swiftUIClientRequests[1].options.body"))
    assert_equal "snapshot-renewed-1", second_request.fetch("snapshot_token")
    assert_equal 3, second_request.dig("changes", "binding.step", "new")

    resolve_request(1, update_payload("snapshot-renewed-2", "stream-renewed-2", "Second response", 3))
    assert_selector "#client-probe-result", text: "Second response"
    assert_selector "#swift-ui-client-probe-123[data-sui-snapshot='snapshot-renewed-2']"

    page.execute_script <<~JAVASCRIPT
      const input = document.querySelector('#client-probe-step')
      input.value = '5'
      input.dispatchEvent(new Event('input', { bubbles: true }))

      const detail = {
        direction: 'forward',
        nested: { count: 2 },
        longText: 'x'.repeat(3000),
        ignoredFunction: () => 'unsafe'
      }
      detail.cycle = detail
      document.querySelector('#nested-action-icon').dispatchEvent(
        new CustomEvent('click', { bubbles: true, detail })
      )
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='3']"

    flushed_request = JSON.parse(page.evaluate_script("window.__swiftUIClientRequests[2].options.body"))
    assert_equal "snapshot-renewed-2", flushed_request.fetch("snapshot_token")
    assert_equal 5, flushed_request.dig("changes", "binding.step", "new")
    resolve_request(2, update_payload("snapshot-before-action", "stream-before-action", "Before action", 5))
    assert_selector "body[data-swift-ui-client-request-count='4']"

    action_request = JSON.parse(page.evaluate_script("window.__swiftUIClientRequests[3].options.body"))
    assert_equal 1, action_request.fetch("render_patch_version")
    assert_equal "button-value", action_request.fetch("target_value")
    assert_equal "button", action_request.dig("target_dataset", "probe")
    refute action_request.fetch("target_dataset").key?("nestedProbe")
    assert_equal "snapshot-before-action", action_request.fetch("snapshot_token")
    event_detail = action_request.fetch("event_detail")
    assert_equal "forward", event_detail.fetch("direction")
    assert_equal({ "count" => 2 }, event_detail.fetch("nested"))
    assert_equal 2048, event_detail.fetch("longText").length
    refute event_detail.key?("ignoredFunction")
    refute event_detail.key?("cycle")

    resolve_request(3, update_payload("snapshot-action", "stream-action", "Action response", 5))
    assert_selector "#client-probe-result", text: "Action response"
    assert_selector "#swift-ui-client-probe-123[data-sui-snapshot='snapshot-action']"
    assert_selector "#swift-ui-client-probe-123[data-sui-stream='stream-action']"

    page.execute_script <<~JAVASCRIPT
      const input = document.querySelector('#client-probe-step')
      input.value = '4'
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='5']"
    resolve_request(4, { error: "Temporarily unavailable" }, status: 503)
    assert_selector "body[data-swift-ui-client-request-count='6']"

    retry_request = JSON.parse(page.evaluate_script("window.__swiftUIClientRequests[5].options.body"))
    assert_equal "snapshot-action", retry_request.fetch("snapshot_token")
    assert_equal 4, retry_request.dig("changes", "binding.step", "new")

    resolve_request(5, update_payload("snapshot-after-retry", "stream-after-retry", "Retry response", 4))
    assert_selector "#client-probe-result", text: "Retry response"

    page.execute_script <<~JAVASCRIPT
      const root = document.querySelector('#swift-ui-client-probe-123')
      root.addEventListener('swift-ui-reactive:capability-error', (event) => {
        event.preventDefault()
        const count = Number(document.body.dataset.swiftUiCapabilityErrors || 0) + 1
        document.body.dataset.swiftUiCapabilityErrors = String(count)
      })
      const input = document.querySelector('#client-probe-step')
      input.value = '6'
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='7']"
    resolve_request(6, { error: "Component changed; refresh and try again" }, status: 409)
    assert_selector "body[data-swift-ui-capability-errors='1']"
    sleep 0.15
    assert_selector "body[data-swift-ui-client-request-count='7']"

    retained_change = page.evaluate_script(<<~JAVASCRIPT)
      document.querySelector('#swift-ui-client-probe-123')
        ._swiftUITransport.pendingChanges['binding.step'].new
    JAVASCRIPT
    assert_equal 6, retained_change
  ensure
    page.execute_script("window.fetch = window.__swiftUIOriginalFetch") if page&.html
  end

  test "applies bounded keyed patches while preserving nodes focus and live input" do
    visit root_path
    install_fetch_probe
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", patch_component_markup)
    wait_for_reactive_controller("swift-ui-patch-probe-789")

    page.execute_script <<~JAVASCRIPT
      const root = document.querySelector('#swift-ui-patch-probe-789')
      window.__swiftUIPreservedItem = root.querySelector('[data-swift-ui-ir-key="sui-000000000000000000000006"]')
      window.__swiftUIPreservedText = root.querySelector('[data-swift-ui-ir-key="sui-000000000000000000000003"]')
      root.addEventListener('swift-ui-render-patch:before', (event) => {
        document.body.dataset.swiftUiPatchBefore = String(event.detail.operationCount)
      })
      root.addEventListener('swift-ui-render-patch:after', (event) => {
        document.body.dataset.swiftUiPatchAfter = String(event.detail.operationCount)
      })

      const input = root.querySelector('#patch-probe-input')
      input.focus()
      input.value = 'draft'
      input.setSelectionRange(1, 4)
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='1']"

    request_data = JSON.parse(page.evaluate_script("window.__swiftUIClientRequests[0].options.body"))
    assert_equal 1, request_data.fetch("render_patch_version")
    assert_equal "draft", request_data.dig("changes", "binding.step", "new")

    resolve_request(0, keyed_patch_payload)

    assert_selector "#swift-ui-patch-probe-789[data-swift-ui-render-mode='patch'][data-swift-ui-patch-operations='6']"
    assert_selector "body[data-swift-ui-patch-before='6'][data-swift-ui-patch-after='6']"
    assert_selector "[data-swift-ui-ir-key='sui-000000000000000000000002'][aria-expanded='true'].updated"
    assert_no_selector "[data-swift-ui-ir-key='sui-000000000000000000000002'][data-old]"
    assert_selector "[data-swift-ui-ir-key='sui-000000000000000000000003']", text: "Updated text"
    assert_no_selector "[data-swift-ui-ir-key='sui-000000000000000000000007']"
    assert_selector "[data-swift-ui-ir-key='sui-00000000000000000000000a']", text: "Inserted"

    order = page.evaluate_script(<<~JAVASCRIPT)
      Array.from(document.querySelector('[data-swift-ui-ir-key="sui-000000000000000000000004"]').children)
        .map((element) => element.dataset.swiftUiIrKey)
    JAVASCRIPT
    assert_equal %w[
      sui-00000000000000000000000a
      sui-000000000000000000000006
      sui-000000000000000000000005
    ], order

    preserved = page.evaluate_script(<<~JAVASCRIPT)
      document.querySelector('[data-swift-ui-ir-key="sui-000000000000000000000006"]') ===
        window.__swiftUIPreservedItem &&
      document.querySelector('[data-swift-ui-ir-key="sui-000000000000000000000003"]') ===
        window.__swiftUIPreservedText
    JAVASCRIPT
    assert preserved, "move and text operations should preserve keyed element objects"

    assert_equal "patch-probe-input", page.evaluate_script("document.activeElement.id")
    assert_equal "draft", find("#patch-probe-input").value
    assert_equal [ 1, 4 ], page.evaluate_script(<<~JAVASCRIPT)
      [document.activeElement.selectionStart, document.activeElement.selectionEnd]
    JAVASCRIPT
    assert_selector "#swift-ui-patch-probe-789[data-sui-snapshot='snapshot-patched']"
  ensure
    restore_fetch_probe
  end

  test "reloads the page after an unprevented malformed patch" do
    visit root_path
    install_fetch_probe
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", patch_component_markup)
    wait_for_reactive_controller("swift-ui-patch-probe-789")

    page.execute_script <<~JAVASCRIPT
      const root = document.querySelector('#swift-ui-patch-probe-789')
      root._swiftUITransport.isDevelopment = () => true
      root.addEventListener('swift-ui-render-patch:error', (event) => {
        sessionStorage.setItem('swift-ui-patch-error-code', event.detail.error.code)
      })
      root.addEventListener('swift-ui-reactive:update-error', () => {
        const count = Number(sessionStorage.getItem('swift-ui-patch-update-errors') || 0) + 1
        sessionStorage.setItem('swift-ui-patch-update-errors', String(count))
      })
      const input = root.querySelector('#patch-probe-input')
      input.value = 'reload-me'
      input.dispatchEvent(new Event('input', { bubbles: true }))
    JAVASCRIPT
    assert_selector "body[data-swift-ui-client-request-count='1']"

    resolve_request(0, {
      snapshot_token: "snapshot-after-malformed-patch",
      stream_token: "stream-after-malformed-patch",
      patch: {
        version: 1,
        component_id: "swift-ui-patch-probe-789",
        operations: [ { op: "remove", key: "sui-ffffffffffffffffffffffff" } ]
      }
    })

    assert_no_selector "#swift-ui-patch-probe-789"
    assert_current_path root_path
    assert_equal "missing_target", page.evaluate_script(
      "sessionStorage.getItem('swift-ui-patch-error-code')"
    )
    assert_equal "1", page.evaluate_script(
      "sessionStorage.getItem('swift-ui-patch-update-errors')"
    )
  ensure
    if page&.html
      page.execute_script <<~JAVASCRIPT
        sessionStorage.removeItem('swift-ui-patch-error-code')
        sessionStorage.removeItem('swift-ui-patch-update-errors')
      JAVASCRIPT
    end
  end

  test "rejects unkeyed and active patch fragments before insertion" do
    visit root_path
    install_fetch_probe
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", patch_component_markup)
    wait_for_reactive_controller("swift-ui-patch-probe-789")

    page.execute_script <<~JAVASCRIPT
      const root = document.querySelector('#swift-ui-patch-probe-789')
      root.addEventListener('swift-ui-render-patch:error', (event) => {
        event.preventDefault()
        const errors = JSON.parse(document.body.dataset.swiftUiPatchSecurityErrors || '[]')
        errors.push(event.detail.error.code)
        document.body.dataset.swiftUiPatchSecurityErrors = JSON.stringify(errors)
        document.body.dataset.swiftUiPatchSecurityErrorCount = String(errors.length)
      })
    JAVASCRIPT

    unsafe_operations = [
      {
        op: "insert", parent_key: "sui-000000000000000000000001", before_key: nil,
        html: '<div data-swift-ui-ir-key="sui-00000000000000000000000c"><span>Unkeyed</span></div>'
      },
      {
        op: "insert", parent_key: "sui-000000000000000000000001", before_key: nil,
        html: '<img data-swift-ui-ir-key="sui-00000000000000000000000d" src="/safe.png" onerror="alert(1)">'
      },
      {
        op: "insert", parent_key: "sui-000000000000000000000001", before_key: nil,
        html: <<~HTML.squish
          <iframe data-swift-ui-ir-key="sui-00000000000000000000000e"
                  title="Unsafe" src="/safe" sandbox srcdoc="&lt;p&gt;unsafe&lt;/p&gt;"></iframe>
        HTML
      },
      {
        op: "insert", parent_key: "sui-000000000000000000000001", before_key: nil,
        html: '<a data-swift-ui-ir-key="sui-00000000000000000000000f" href="javascript:alert(1)">Unsafe</a>'
      },
      {
        op: "attributes", key: "sui-00000000000000000000000b",
        attributes: { "href" => "javascript:alert(1)" }
      }
    ]

    unsafe_operations.each_with_index do |operation, index|
      page.execute_script <<~JAVASCRIPT
        const input = document.querySelector('#patch-probe-input')
        input.value = #{"unsafe-#{index}".to_json}
        input.dispatchEvent(new Event('input', { bubbles: true }))
      JAVASCRIPT
      assert_selector "body[data-swift-ui-client-request-count='#{index + 1}']"

      resolve_request(index, {
        snapshot_token: "snapshot-after-security-#{index}",
        stream_token: "stream-after-security-#{index}",
        patch: {
          version: 1,
          component_id: "swift-ui-patch-probe-789",
          operations: [ operation ]
        }
      })

      assert_selector "body[data-swift-ui-patch-security-error-count='#{index + 1}']"
      assert_selector "#swift-ui-patch-probe-789"
      wait_until do
        !page.evaluate_script(
          "document.querySelector('#swift-ui-patch-probe-789')._swiftUITransport.updateInFlight"
        )
      end
    end

    assert_equal %w[
      missing_fragment_key
      active_fragment
      active_fragment
      unsafe_url
      unsafe_url
    ], JSON.parse(page.evaluate_script("document.body.dataset.swiftUiPatchSecurityErrors"))
    assert_no_selector <<~CSS.squish
      [data-swift-ui-ir-key='sui-00000000000000000000000c'],
      [data-swift-ui-ir-key='sui-00000000000000000000000d'],
      [data-swift-ui-ir-key='sui-00000000000000000000000e'],
      [data-swift-ui-ir-key='sui-00000000000000000000000f']
    CSS
    assert_selector "[data-swift-ui-ir-key='sui-00000000000000000000000b'][href='/safe']"
  ensure
    restore_fetch_probe
  end

  private

  def install_fetch_probe
    page.execute_script <<~JAVASCRIPT
      window.__swiftUIClientRequests = []
      window.__swiftUIOriginalFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const path = String(url)
        if (!path.includes('/client-probe/') && !path.includes('/swift_ui/actions')) {
          return window.__swiftUIOriginalFetch(url, options)
        }

        return new Promise((resolve) => {
          window.__swiftUIClientRequests.push({ path, options, resolve })
          document.body.dataset.swiftUiClientRequestCount = String(window.__swiftUIClientRequests.length)
        })
      }
    JAVASCRIPT
  end

  def restore_fetch_probe
    return unless page&.html

    page.execute_script <<~JAVASCRIPT
      if (window.__swiftUIOriginalFetch) window.fetch = window.__swiftUIOriginalFetch
    JAVASCRIPT
  rescue Selenium::WebDriver::Error::WebDriverError
    nil
  end

  def wait_for_reactive_controller(component_id)
    wait_until do
      page.evaluate_script(<<~JAVASCRIPT)
        Boolean(document.querySelector('##{component_id}')?._swiftUITransport)
      JAVASCRIPT
    end
  end

  def component_markup
    <<~HTML
      <div id="swift-ui-client-probe-123"
           data-sui-root="1"
           data-sui-id="swift-ui-client-probe-123"
           data-sui-component="ReactiveCounterComponent"
           data-sui-stream="stream-initial"
           data-sui-snapshot="snapshot-initial"
           data-sui-update-url="/client-probe/update"
           data-sui-debounce="0">
        <input id="client-probe-step" value="1" data-sui-binding="step" data-sui-binding-type="integer">
        <span id="client-probe-result">Initial</span>
        <button type="button" value="button-value" data-probe="button"
                data-sui-actions='{"click":"increment-123"}'>
          <span id="nested-action-icon" data-nested-probe="icon">+</span>
        </button>
      </div>
      <div id="swift-ui-client-probe-456"
           data-sui-root="1"
           data-sui-id="swift-ui-client-probe-456"
           data-sui-component="ReactiveCounterComponent"
           data-sui-stream="stream-second"
           data-sui-snapshot="snapshot-second"
           data-sui-update-url="/client-probe/update"></div>
    HTML
  end

  def patch_component_markup
    <<~HTML
      <div id="swift-ui-patch-probe-789"
           data-swift-ui-ir-key="sui-000000000000000000000001"
           data-sui-root="1"
           data-sui-id="swift-ui-patch-probe-789"
           data-sui-component="ReactiveCounterComponent"
           data-sui-stream="stream-initial"
           data-sui-snapshot="snapshot-initial"
           data-sui-update-url="/client-probe/update"
           data-sui-debounce="0">
        <div data-swift-ui-ir-key="sui-000000000000000000000002" data-old="true">Attributes</div>
        <span data-swift-ui-ir-key="sui-000000000000000000000003">Initial text</span>
        <ul data-swift-ui-ir-key="sui-000000000000000000000004">
          <li data-swift-ui-ir-key="sui-000000000000000000000005">First</li>
          <li data-swift-ui-ir-key="sui-000000000000000000000006">Second</li>
        </ul>
        <div data-swift-ui-ir-key="sui-000000000000000000000007">Remove me</div>
        <label data-swift-ui-ir-key="sui-000000000000000000000008">
          <input id="patch-probe-input"
                 data-swift-ui-ir-key="sui-000000000000000000000009"
                 data-sui-binding="step"
                 value="initial">
        </label>
        <a data-swift-ui-ir-key="sui-00000000000000000000000b" href="/safe">Safe link</a>
      </div>
    HTML
  end

  def keyed_patch_payload
    {
      snapshot_token: "snapshot-patched",
      stream_token: "stream-patched",
      patch: {
        version: 1,
        component_id: "swift-ui-patch-probe-789",
        operations: [
          {
            op: "attributes",
            key: "sui-000000000000000000000002",
            attributes: { "class" => "updated", "aria-expanded" => "true" }
          },
          { op: "text", key: "sui-000000000000000000000003", value: "Updated text" },
          { op: "remove", key: "sui-000000000000000000000007" },
          {
            op: "insert",
            parent_key: "sui-000000000000000000000004",
            before_key: "sui-000000000000000000000005",
            html: '<li data-swift-ui-ir-key="sui-00000000000000000000000a">Inserted</li>'
          },
          {
            op: "move",
            key: "sui-000000000000000000000006",
            parent_key: "sui-000000000000000000000004",
            before_key: "sui-000000000000000000000005"
          },
          {
            op: "replace",
            key: "sui-000000000000000000000008",
            html: <<~HTML.squish
              <label data-swift-ui-ir-key="sui-000000000000000000000008">
                <input id="patch-probe-input"
                       data-swift-ui-ir-key="sui-000000000000000000000009"
                       data-sui-binding="step"
                       value="server">
              </label>
            HTML
          }
        ]
      }
    }
  end

  def update_payload(snapshot, stream, text, value)
    {
      snapshot_token: snapshot,
      html: <<~HTML.squish
        <div data-sui-root="1"
             data-sui-snapshot="#{snapshot}"
             data-sui-stream="#{stream}">
          <input id="client-probe-step" value="#{value}" data-sui-binding="step" data-sui-binding-type="integer">
          <span id="client-probe-result">#{text}</span>
          <button type="button" value="button-value" data-probe="button"
                  data-sui-actions='{"click":"increment-123"}'>
            <span id="nested-action-icon" data-nested-probe="icon">+</span>
          </button>
        </div>
      HTML
    }
  end

  def resolve_request(index, payload, status: 200)
    page.execute_script(<<~JAVASCRIPT, index, payload.to_json, status)
      window.__swiftUIClientRequests[arguments[0]].resolve(
        new Response(arguments[1], {
          status: arguments[2],
          headers: { 'Content-Type': 'application/json' }
        })
      )
    JAVASCRIPT
  end

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    until yield
      raise "timed out waiting for browser state" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end
end
