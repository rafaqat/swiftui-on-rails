# frozen_string_literal: true

require "test_helper"

module Showcase
  class MissionControlControllerTest < ActionDispatch::IntegrationTest
    test "renders the standalone server-authoritative command center" do
      get showcase_mission_control_path

      assert_response :success
      assert_select "#atlas-mission-control"
      assert_select "#atlas-flight-plan"
      assert_select "#atlas-systems"
      assert_select "#atlas-alerts"
      assert_select "#atlas-documents"
      assert_select "form input[name='authenticity_token']", minimum: 1 if ActionController::Base.allow_forgery_protection
    end

    test "HTML sequence moves use PRG and persist only known stable keys" do
      patch showcase_mission_control_sequence_path,
        params: { reorder: { item_key: "range", target_key: "payload", placement: "before" } }

      assert_response :see_other
      assert_redirected_to "#{showcase_mission_control_path}#atlas-flight-plan"

      get showcase_mission_control_document_export_path
      assert_equal %w[weather range payload propellant guidance], export_sequences

      patch showcase_mission_control_sequence_path,
        params: { reorder: { item_key: "Kernel", direction: "up" } }
      assert_response :see_other
      assert_equal "Unknown mission sequence item", flash[:alert]

      get showcase_mission_control_document_export_path
      assert_equal %w[weather range payload propellant guidance], export_sequences
    end

    test "system and alert commands are scoped Turbo replacements with count interlocks" do
      patch showcase_mission_control_system_action_path(system: "range", mission_action: "go"),
        headers: turbo_headers
      assert_response :success
      assert_select "turbo-stream[action='replace'][target='atlas-mission-control']"
      assert_includes response.body, "100%"

      patch showcase_mission_control_alert_action_path(alert: "winds", mission_action: "escalate"),
        headers: turbo_headers
      assert_response :success
      assert_includes response.body, "ESCALATED"

      post showcase_mission_control_advance_path, headers: turbo_headers
      assert_response :unprocessable_entity
      assert_includes response.body, "Resolve escalated flight alerts"

      patch showcase_mission_control_alert_action_path(alert: "winds", mission_action: "acknowledge"),
        headers: turbo_headers
      post showcase_mission_control_advance_path, headers: turbo_headers
      assert_response :success
      assert_includes response.body, "T−04"
    end

    test "reset restores the verified baseline through an HTML fallback" do
      patch showcase_mission_control_system_action_path(system: "range", mission_action: "go")
      patch showcase_mission_control_sequence_path,
        params: { reorder: { item_key: "range", direction: "up" } }
      post showcase_mission_control_reset_path

      assert_response :see_other
      assert_redirected_to "#{showcase_mission_control_path}#atlas-mission-control"
      get showcase_mission_control_document_export_path
      assert_equal Showcase::MissionControlState::SEQUENCE.keys, export_sequences
    end

    test "document import and creation require signed provenance" do
      token = SwiftUIRails::DocumentWorkflow.sign_creation_context(
        source: :import,
        metadata: { mission: "atlas-7", surface: "showcase" }
      )
      upload = fixture_file_upload("workflow-demo.txt", "text/plain")

      post showcase_mission_control_document_import_path,
        params: { document: { creation_context: token, file: upload } }
      assert_response :see_other
      follow_redirect!
      assert_response :success
      assert_select "#atlas-documents", text: /workflow-demo\.txt/

      post showcase_mission_control_document_import_path,
        params: { document: { creation_context: "tampered", file: upload } }
      assert_response :see_other
      assert_match(/invalid or expired/, flash[:alert])

      creation_token = SwiftUIRails::DocumentWorkflow.sign_creation_context(
        source: :template,
        metadata: { mission: "atlas-7", template: "console-log" }
      )
      post showcase_mission_control_documents_path,
        params: { document: { creation_context: creation_token } }
      follow_redirect!
      assert_select "#atlas-documents", text: /Atlas launch brief\.txt/
    end

    test "export streams a safe CSV from normalized server state" do
      get showcase_mission_control_document_export_path

      assert_response :success
      assert_equal "text/csv; charset=utf-8", "#{response.media_type}; charset=#{response.charset}"
      assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
      assert_match(/atlas-mission-plan\.csv/, response.headers.fetch("Content-Disposition"))
      sequences = export_sequences
      assert_equal Showcase::MissionControlState::SEQUENCE.keys, sequences
      assert sequences.all? { |sequence| Showcase::MissionControlState::SEQUENCE.key?(sequence) }
    end

    test "only the exact Storybook surface selects the hard-coded story redirect" do
      patch showcase_mission_control_sequence_path(surface: "storybook"),
        params: { reorder: { item_key: "range", direction: "up" } }
      assert_redirected_to story_path(
        story: "atlas_mission_control",
        variant: "command_center",
        anchor: "atlas-flight-plan"
      )

      patch showcase_mission_control_sequence_path(surface: "https://attacker.test/steal"),
        params: { reorder: { item_key: "range", direction: "up" } },
        headers: { "HTTP_REFERER" => "https://attacker.test/steal" }
      assert_redirected_to "#{showcase_mission_control_path}#atlas-flight-plan"
    end

    test "route constraints reject unknown systems alerts and client-selected methods" do
      patch "/showcase/mission-control/systems/Object/go"
      assert_response :not_found

      patch "/showcase/mission-control/systems/range/constantize"
      assert_response :not_found

      patch "/showcase/mission-control/alerts/admin/acknowledge"
      assert_response :not_found

      patch "/showcase/mission-control/alerts/winds/send"
      assert_response :not_found
    end

    private

    def turbo_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end

    def export_sequences
      response.body.lines.drop(1).map { |line| line.split(",", 4).fetch(1) }
    end
  end
end
