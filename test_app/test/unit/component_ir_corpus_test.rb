# frozen_string_literal: true

require "test_helper"

# This is the wholesale-renderer gate. Every concrete SwiftUI Rails component
# in the demo application must have deterministic construction data, must
# render through RenderIR, and must produce a serializable immutable document.
class ComponentIrCorpusTest < ActiveSupport::TestCase
  test "the fixture corpus covers every concrete application component" do
    component_classes = SwiftUi::LintComponentFixtures.concrete_component_classes
    uncovered = SwiftUi::LintComponentFixtures.uncovered_component_classes

    assert_operator component_classes.length, :>=, 50, "component discovery looks incomplete"
    assert_empty uncovered.map(&:name), "Missing deterministic IR fixtures"
  end

  test "every concrete component renders through canonical RenderIR" do
    failures = SwiftUi::LintComponentFixtures.concrete_component_classes.filter_map do |component_class|
      SwiftUi::LintComponentFixtures.cases_for(component_class).filter_map do |fixture_case|
        verify_case(component_class, fixture_case)
      end
    end.flatten

    assert_empty failures, "Component RenderIR failures:\n#{failures.join("\n")}"
  end

  private

  def verify_case(component_class, fixture_case)
    component = fixture_case.build(view_context: lint_view_context)
    html = ApplicationController.render(component, layout: false).to_s
    label = "#{component_class.name} [#{fixture_case.name}]"

    return "#{label}: rendered the error boundary" if html.include?("swift-ui-error-boundary")
    return "#{label}: rendered empty HTML" if html.empty?
    return "#{label}: does not expose #last_render_ir" unless component.respond_to?(:last_render_ir)

    document = component.last_render_ir
    unless document.is_a?(SwiftUIRails::RenderIR::Document)
      return "#{label}: last_render_ir is #{document.class}, expected RenderIR::Document"
    end
    return "#{label}: RenderIR has no nodes" unless document.each_node.any?

    SwiftUIRails::RenderIR::Validator.validate!(document)
    round_trip = SwiftUIRails::RenderIR::Document.from_json(document.canonical_json)
    return if round_trip == document

    "#{label}: canonical JSON round-trip changed the RenderIR document"
  rescue StandardError => error
    "#{component_class.name} [#{fixture_case.name}]: #{error.class}: #{error.message}"
  end

  def lint_view_context
    @lint_view_context ||= begin
      controller = StorybookController.new
      request = ActionDispatch::TestRequest.create
      request.set_header("action_dispatch.routes", Rails.application.routes)
      controller.set_request!(request)
      controller.set_response!(ActionDispatch::TestResponse.new)
      controller.view_context
    end
  end
end
