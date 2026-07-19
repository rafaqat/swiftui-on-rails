# frozen_string_literal: true

require "test_helper"

class EnvironmentInteractionJavascriptTest < ActionDispatch::IntegrationTest
  TEMPLATE_PATH = Rails.root.join(
    "..", "lib", "generators", "swift_ui_rails", "install", "templates",
    "swift_ui_runtime.js"
  ).expand_path

  test "semantic runtime serves the finite interaction protocol" do
    get ActionController::Base.helpers.asset_path("swift_ui_runtime.js")

    assert_response :success
    assert_match(/class InteractionBehavior/, response.body)
    assert_includes response.body, "'data-sui-focus'"
    assert_includes response.body, "'data-sui-long-press'"
    assert_includes response.body, "'data-sui-drag'"
    assert_includes response.body, "'data-sui-keypress'"
    assert_match(/new AbortController\(\)/, response.body)
    assert_match(/abortTask\(\)/, response.body)
    assert_match(/swift-ui-focus-change/, response.body)
    assert_match(/swift-ui-long-press/, response.body)
    assert_match(/swift-ui-drag-change/, response.body)
    assert_match(/\['Enter', ' '\]\.includes\(event\.key\)/, response.body)
    refute_match(/extends\s+Controller/, response.body)
  end

  test "install template stays byte-for-byte synchronized with the exercised runtime" do
    runtime_path = Rails.root.join("app/javascript/swift_ui_runtime.js")

    assert_equal File.binread(runtime_path), File.binread(TEMPLATE_PATH)
  end

  test "delegated routing resolves opaque semantic actions by event type" do
    get ActionController::Base.helpers.asset_path("swift_ui_runtime.js")

    assert_response :success
    assert_includes response.body, "const ACTION_SELECTOR = '[data-sui-actions]"
    assert_match(/event\.target\.closest\(ACTION_SELECTOR\)/, response.body)
    assert_match(/findActionId\(target, event\.type\)/, response.body)
    assert_match(/JSON\.parse\(actionMap\)\[eventType\]/, response.body)
  end

  test "Ruby and browser action event vocabularies are identical" do
    runtime = Rails.root.join("app/javascript/swift_ui_runtime.js").read
    declaration = runtime.match(
      /const DELEGATED_ACTION_EVENTS = Object\.freeze\(\[(.*?)\]\)/m
    )&.[](1)
    assert declaration, "runtime action event declaration is missing"

    browser_events = declaration.scan(/['"]([^'"]+)['"]/).flatten
    ruby_events = SwiftUIRails::RenderIR::SemanticActionEvents::ALL
    assert_equal ruby_events, browser_events
    %w[focusin focusout mouseover].each { |event_name| assert_includes browser_events, event_name }
    %w[focus blur mouseenter mouseleave keypress resize scroll unload touchstart].each do |event_name|
      refute_includes browser_events, event_name
    end
  end

  test "install generator packages one framework-owned runtime" do
    generator = File.read(Rails.root.join("..", "lib/generators/swift_ui_rails/install/install_generator.rb"))

    assert_includes generator, 'template "swift_ui_runtime.js", "app/javascript/swift_ui_runtime.js"'
    refute_match(/swift_ui_(?:interaction|component)_controller/, generator)
  end
end
