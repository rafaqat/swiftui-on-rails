# frozen_string_literal: true

require "test_helper"

class JavascriptIntegrationTest < ActionDispatch::IntegrationTest
  test "application loads the framework-free semantic runtime" do
    application = fetch_asset("application.js")
    assert_includes application, 'import "swift_ui_runtime"'
    refute_includes application, 'import "controllers"'
    refute_includes application, 'import "motion_stream_transitions"'

    importmap = Rails.root.join("config/importmap.rb").read
    assert_includes importmap, 'pin "swift_ui_runtime"'
    refute_includes importmap, '@hotwired/stimulus'
    refute_includes importmap, "pin_all_from \"app/javascript/controllers\""
  end

  test "semantic runtime delegates events and never embeds application behavior" do
    runtime = fetch_asset("swift_ui_runtime.js")

    assert_includes runtime, "class SwiftUIRuntime"
    assert_includes runtime, "class SwiftUIReactiveTransport"
    assert_includes runtime, "class SwiftUIActionTransport"
    assert_includes runtime, "const ACTION_SELECTOR = '[data-sui-actions]"
    assert_includes runtime, "const BINDING_SELECTOR = '[data-sui-binding]"
    assert_includes runtime, "new MutationObserver(this.handleMutations)"
    assert_includes runtime, "handleTurboStreamRender(event)"
    assert_includes runtime, "EXIT_TRANSITION_FALLBACK_MS = 450"
    refute_includes runtime, "@hotwired/stimulus"
    refute_match(/extends\s+Controller/, runtime)
  end

  test "reactive browser runtime serializes capabilities retries changes and shares cable" do
    reactive = fetch_asset("swift_ui_runtime.js")

    assert_includes reactive, "if (this.updateInFlight || this.externalUpdates > 0 || this.retryTimer) return"
    assert_includes reactive, "this.mergePendingChanges(changes, { preserveNewer: true })"
    assert_includes reactive, "snapshot_token: this.snapshotTokenValue"
    assert_includes reactive, "render_patch_version: RENDER_PATCH_VERSION"
    assert_includes reactive, "applyRenderPatch(this.element, data.patch"
    assert_includes reactive, 'this.element.dataset.swiftUiRenderMode = "html"'
    assert_includes reactive, "this.applyRenewedCapabilities(data)"
    assert_includes reactive, "MAX_UPDATE_RETRIES"
    assert_includes reactive, "CAPABILITY_RELOAD_GUARD_MS"
    assert_includes reactive, "sessionStorage.setItem(key"
    assert_includes reactive, "this.dispatch('capability-error'"
    assert_includes reactive, "const sharedCable ="
    assert_includes reactive, "this.consumer = sharedCable.acquire()"
    assert_includes reactive, "sharedCable.release()"
    assert_includes reactive, "unsubscribeFromUpdates({ releaseConsumer: false })"
  end

  test "delegated component actions sanitize event data and apply renewed capabilities" do
    component = fetch_asset("swift_ui_runtime.js")

    assert_includes component, "handleAction(event, target)"
    assert_includes component, "target_value: this.getTargetValue(target)"
    assert_includes component, "target_dataset: Object.fromEntries(Object.entries(target.dataset))"
    refute_includes component, "target_value: this.getTargetValue(event)"
    assert_includes component, "await reactiveController.flushPendingUpdates()"
    assert_includes component, "reactiveController.beginExternalUpdate()"
    assert_includes component, "reactiveController.applyRenderResponse(data, focusTarget)"
    assert_includes component, "actionData.render_patch_version = RENDER_PATCH_VERSION"
    assert_includes component, "this.enqueueAction(actionData, reactiveRoot, target)"
    assert_includes component, "this.preventConflictingNativeDefault(event, target)"
    assert_includes component, "if (!hasReactiveCapability && !hasStoryCapability) return false"
    assert_includes component, "const eventDetail = sanitizeEventDetail(event.detail)"
    assert_includes component, "MAX_EVENT_DETAIL_DEPTH = 4"
    assert_includes component, "MAX_EVENT_DETAIL_ENTRIES = 64"
    assert_includes component, "MAX_EVENT_DETAIL_BYTES = 16 * 1024"
    assert_includes component, "MAX_ACTION_PAYLOAD_BYTES = 64 * 1024"
    assert_includes component, "seen.has(value)"
    assert_includes component, "typeof value !== 'object'"
  end

  test "render patch runtime is pinned and enforces the bounded v1 protocol" do
    importmap = Rails.root.join("config/importmap.rb").read
    assert_includes importmap, 'pin "swift_ui_render_patch"'

    runtime = fetch_asset("swift_ui_render_patch.js")
    assert_includes runtime, "RENDER_PATCH_VERSION = 1"
    assert_includes runtime, "MAX_OPERATIONS = 512"
    assert_includes runtime, "KEY_PATTERN = /^sui-[0-9a-f]{24}$/"
    assert_includes runtime, "Every render patch fragment element requires a key."
    assert_includes runtime, "FORBIDDEN_FRAGMENT_ATTRIBUTES"
    assert_includes runtime, "URL_ATTRIBUTES"
    assert_includes runtime, 'root.dataset.swiftUiRenderMode = "patch"'
    refute_match(/\beval\s*\(|\bnew\s+Function\b/, runtime)
  end

  test "allowlisted behavior registry covers every gem-owned enhancement" do
    runtime = fetch_asset("swift_ui_runtime.js")

    %w[InteractionBehavior PresentationBehavior WorkflowBehavior AsyncImageBehavior CanvasBehavior].each do |behavior|
      assert_includes runtime, "class #{behavior}"
    end
    assert_includes runtime, "switch (command.type)"
    assert_includes runtime, "context.fillRect"
    assert_includes runtime, "context.arc"
    refute_match(/\beval\s*\(|\bnew\s+Function\b/, runtime)
  end

  private

  def fetch_asset(logical_path)
    get ActionController::Base.helpers.asset_path(logical_path)
    assert_response :success
    response.body
  end
end
