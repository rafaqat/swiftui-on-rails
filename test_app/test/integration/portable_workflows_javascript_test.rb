# frozen_string_literal: true

require "test_helper"

class PortableWorkflowsJavascriptTest < ActionDispatch::IntegrationTest
  test "semantic runtime exposes every finite workflow enhancement" do
    get ActionController::Base.helpers.asset_path("swift_ui_runtime.js")

    assert_response :success
    assert_match(/class WorkflowBehavior/, response.body)
    assert_includes response.body, "selector: '[data-sui-workflow]'"
    %w[
      dragstart
      dragover
      drop
      swipeStart
      swipeMove
      swipeEnd
      swipeCancel
      validateFiles
      beginUpload
      directUploadInitialize
      directUploadStart
      directUploadProgress
      directUploadError
      directUploadEnd
      turboSubmitEnd
    ].each do |action|
      assert_match(/\b#{action}\(event\)|\b#{action}\(\)/, response.body, "missing #{action} action")
    end
    assert_match(/requestSubmit\(\)/, response.body)
    assert_match(/setCustomValidity/, response.body)
    assert_includes response.body, "event.type === 'dragend'"
    assert_includes response.body, "event.type === 'turbo:submit-start'"
    assert_includes response.body, "event.target.closest?.('button, a, input, select, textarea, form')"
    refute_match(/\beval\s*\(/, response.body)
  end

  test "install generator packages workflows inside the exact single runtime" do
    generator_source = Rails.root.join(
      "..",
      "lib/generators/swift_ui_rails/install/install_generator.rb"
    ).read
    template = Rails.root.join(
      "..",
      "lib/generators/swift_ui_rails/install/templates/swift_ui_runtime.js"
    )
    installed = Rails.root.join("app/javascript/swift_ui_runtime.js")

    assert_includes generator_source, 'template "swift_ui_runtime.js", "app/javascript/swift_ui_runtime.js"'
    refute_match(/swift_ui_workflow_controller/, generator_source)
    assert template.file?
    assert_equal template.read, installed.read
  end
end
