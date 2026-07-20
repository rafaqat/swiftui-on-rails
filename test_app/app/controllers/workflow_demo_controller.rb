# frozen_string_literal: true

class WorkflowDemoController < ApplicationController
  ITEM_KEYS = %w[research design build release].freeze
  MESSAGE_KEYS = %w[roadmap incident].freeze
  DOCUMENT_MAX_BYTES = 1.megabyte
  DOCUMENT_CONTENT_TYPES = %w[text/plain application/pdf].freeze

  def reorder
    values = params.expect(reorder: %i[item_key direction target_key placement])
    order = current_order
    item_key = values[:item_key].to_s
    return reject_workflow("Unknown reorder item") unless order.include?(item_key)

    destination = if values[:direction].present?
      directional_destination(order, item_key, values[:direction].to_s)
    else
      targeted_destination(order, item_key, values[:target_key].to_s, values[:placement].to_s)
    end
    return reject_workflow("Invalid reorder request") unless destination

    order.delete(item_key)
    order.insert(destination.clamp(0, order.length), item_key)
    session[:workflow_demo_order] = order
    redirect_to workflow_story_path(anchor: "workflow-reorder"), notice: "Order updated"
  end

  def message_action
    message = params[:message].to_s
    action = params[:workflow_action].to_s
    unless MESSAGE_KEYS.include?(message) && %w[archive delete].include?(action)
      return reject_workflow("Unknown message action")
    end

    session[:workflow_demo_message_status] = "#{message.humanize} marked #{action}d"
    redirect_to workflow_story_path(anchor: "workflow-swipe"), notice: "Message action recorded"
  end

  def import_document
    document = params.expect(document: %i[creation_context file])
    context = SwiftUIRails::DocumentWorkflow.verify_creation_context!(
      document[:creation_context]
    )
    upload = document[:file]
    SwiftUIRails::DocumentWorkflow.validate_upload!(
      upload,
      max_bytes: DOCUMENT_MAX_BYTES,
      content_types: DOCUMENT_CONTENT_TYPES
    )

    session[:workflow_demo_document_status] = {
      filename: File.basename(upload.original_filename.to_s),
      bytes: upload.size,
      source: context.fetch(:source).to_s
    }
    redirect_to workflow_story_path(anchor: "workflow-documents"), notice: "Document inspected safely"
  rescue SwiftUIRails::DocumentWorkflow::ValidationError, ActionController::ParameterMissing => error
    redirect_to workflow_story_path(anchor: "workflow-documents"), alert: error.message
  end

  def create_document
    document = params.expect(document: [:creation_context])
    context = SwiftUIRails::DocumentWorkflow.verify_creation_context!(
      document[:creation_context]
    )
    session[:workflow_demo_document_status] = {
      filename: "Untitled report.txt",
      bytes: 0,
      source: context.fetch(:source).to_s
    }
    redirect_to workflow_story_path(anchor: "workflow-documents"), notice: "Document creation context verified"
  rescue SwiftUIRails::DocumentWorkflow::ValidationError, ActionController::ParameterMissing => error
    redirect_to workflow_story_path(anchor: "workflow-documents"), alert: error.message
  end

  def export_document
    body = <<~CSV
      stage,status
      research,complete
      design,active
      build,planned
      release,planned
    CSV
    send_data(
      body,
      type: "text/csv; charset=utf-8",
      disposition: "attachment",
      filename: "workflow-status.csv"
    )
  end

  private

  def current_order
    candidate = Array(session[:workflow_demo_order]).map(&:to_s)
    candidate.sort == ITEM_KEYS.sort ? candidate : ITEM_KEYS.dup
  end

  def directional_destination(order, item_key, direction)
    index = order.index(item_key)
    case direction
    when "up" then [index - 1, 0].max
    when "down" then [index + 1, order.length - 1].min
    end
  end

  def targeted_destination(order, item_key, target_key, placement)
    return unless ITEM_KEYS.include?(target_key) && target_key != item_key
    return unless %w[before after].include?(placement)

    reduced = order - [item_key]
    target_index = reduced.index(target_key)
    target_index + (placement == "after" ? 1 : 0)
  end

  def workflow_story_path(anchor: nil)
    story_path(
      story: "wwdc26_workflows",
      variant: "portable_workflows",
      anchor: anchor
    )
  end

  def reject_workflow(message)
    redirect_to workflow_story_path, alert: message
  end
end
