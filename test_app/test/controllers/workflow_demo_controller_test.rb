# frozen_string_literal: true

require "test_helper"

class WorkflowDemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    StorybookStoryRegistry.reload!
  end

  test "direct story renders every portable workflow with real CSRF forms" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get story_path(story: "wwdc26_workflows", variant: "portable_workflows")

    assert_response :success
    assert_select "#delivery-order[data-sui-workflow]"
    assert_select "#delivery-order[data-controller]", count: 0
    assert_select "#workflow-swipe .swift-ui-swipe-action", minimum: 4
    assert_select "#workflow-document-import[enctype='multipart/form-data']"
    assert_select "form input[name='authenticity_token']", minimum: 1
    assert_select ".swift-ui-document-export[href='/workflow_demo/documents/export']"
    assert_select ".text-red-600", count: 0
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "keyboard reorder endpoint accepts only known keys and persists authoritative order" do
    patch workflow_demo_reorder_path, params: { reorder: { item_key: "research", direction: "down" } }

    assert_redirected_to story_path(
      story: "wwdc26_workflows",
      variant: "portable_workflows",
      anchor: "workflow-reorder"
    )
    follow_redirect!
    assert_response :success
    labels = css_select("#delivery-order .swift-ui-reorder-content .text-lg").map(&:text)
    assert_equal ["Design", "Research", "Build", "Release"], labels

    patch workflow_demo_reorder_path, params: { reorder: { item_key: "admin", direction: "up" } }
    assert_redirected_to story_path(story: "wwdc26_workflows", variant: "portable_workflows")
    assert_equal "Unknown reorder item", flash[:alert]
  end

  test "drag contract validates target key and placement" do
    patch workflow_demo_reorder_path,
      params: { reorder: { item_key: "release", target_key: "design", placement: "before" } }
    follow_redirect!

    labels = css_select("#delivery-order .swift-ui-reorder-content .text-lg").map(&:text)
    assert_equal ["Research", "Release", "Design", "Build"], labels

    patch workflow_demo_reorder_path,
      params: { reorder: { item_key: "release", target_key: "design", placement: "inside" } }
    assert_equal "Invalid reorder request", flash[:alert]
  end

  test "swipe alternatives execute through constrained Rails routes" do
    patch workflow_demo_message_action_path(message: "roadmap", workflow_action: "archive")
    follow_redirect!

    assert_response :success
    assert_select "[role='status']", text: /Roadmap marked archived/

    patch "/workflow_demo/messages/admin/archive"
    assert_response :not_found
  end

  test "document import verifies provenance and bounded upload before reporting status" do
    token = SwiftUIRails::DocumentWorkflow.sign_creation_context(
      source: :import,
      metadata: { surface: "controller-test" }
    )
    upload = fixture_file_upload("workflow-demo.txt", "text/plain")

    post workflow_demo_document_import_path,
      params: { document: { creation_context: token, file: upload } }
    follow_redirect!

    assert_response :success
    assert_select "[role='status']", text: /workflow-demo\.txt · import/

    post workflow_demo_document_import_path,
      params: { document: { creation_context: "tampered", file: upload } }
    assert_redirected_to story_path(
      story: "wwdc26_workflows",
      variant: "portable_workflows",
      anchor: "workflow-documents"
    )
    assert_match(/invalid or expired/, flash[:alert])
  end

  test "document creation verifies signed source and export streams safe headers" do
    token = SwiftUIRails::DocumentWorkflow.sign_creation_context(
      source: :template,
      metadata: { template_id: "weekly-status" }
    )
    post workflow_demo_documents_path, params: { document: { creation_context: token } }
    follow_redirect!

    assert_select "[role='status']", text: /Untitled report\.txt · template/

    get workflow_demo_document_export_path
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=#{response.charset}"
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    assert_match(/workflow-status\.csv/, response.headers.fetch("Content-Disposition"))
    assert_includes response.body, "research,complete"
  end
end
