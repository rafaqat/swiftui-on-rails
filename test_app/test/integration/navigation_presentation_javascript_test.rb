# frozen_string_literal: true

require "test_helper"

class NavigationPresentationJavascriptTest < ActionDispatch::IntegrationTest
  test "semantic runtime serves every finite presentation behavior" do
    get ActionController::Base.helpers.asset_path("swift_ui_runtime.js")

    assert_response :success
    assert_match(/class PresentationBehavior/, response.body)
    assert_includes response.body, "[data-sui-tabs]"
    assert_includes response.body, "[data-sui-popover]"
    assert_includes response.body, "[data-sui-toolbar]"
    assert_includes response.body, "[data-sui-dialog]"
    %w[
      open
      handleCancel
      closeOnBackdrop
      restoreFocus
      selectTab
      navigateTabs
      closePopover
      syncPopover
      navigateToolbar
      syncToolbarOverflow
    ].each do |behavior|
      assert_match(/\b#{behavior}\(/, response.body, "missing #{behavior} behavior")
    end
    assert_match(/showModal\(\)/, response.body)
    assert_match(/history\.pushState/, response.body)
    assert_match(/window\.addEventListener\(['"]popstate['"]/, response.body)
    assert_match(/window\.addEventListener\(['"]hashchange['"]/, response.body)
    assert_match(/tabForCurrentLocation/, response.body)
    assert_match(/localTabPanel/, response.body)
    assert_match(/new ResizeObserver/, response.body)
    assert_match(/suiToolbarPriority/, response.body)
    assert_match(/nearestScrollSource/, response.body)
  end

  test "install generator packages presentation inside the single runtime" do
    generator_source = Rails.root.join(
      "..",
      "lib/generators/swift_ui_rails/install/install_generator.rb"
    ).read
    template = Rails.root.join(
      "..",
      "lib/generators/swift_ui_rails/install/templates/swift_ui_runtime.js"
    )

    assert_includes generator_source, 'template "swift_ui_runtime.js", "app/javascript/swift_ui_runtime.js"'
    refute_match(/swift_ui_presentation_controller/, generator_source)
    assert template.file?
    assert_equal template.read, Rails.root.join("app/javascript/swift_ui_runtime.js").read

    stylesheet_template = Rails.root.join(
      "..",
      "lib/generators/swift_ui_rails/install/templates/swift_ui_rails.css"
    ).read
    assert_includes generator_source, 'template "swift_ui_rails.css"'
    assert_includes stylesheet_template, ".swift-ui-toolbar-overflow-items"
    assert_includes stylesheet_template, '[data-sui-toolbar-minimized="true"]'
  end
end
