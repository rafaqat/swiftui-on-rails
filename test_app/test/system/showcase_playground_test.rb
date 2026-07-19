# frozen_string_literal: true

require "application_system_test_case"

class ShowcasePlaygroundTest < ApplicationSystemTestCase
  test "edits both buffers and renders through a Rails round trip" do
    visit showcase_playground_path

    assert_selector "#swift-rails-playground[data-playground-mode='server-round-trip']"
    assert_selector "#playground-run-form[data-turbo='false']"
    assert_no_selector "[data-controller], [data-action], [data-playground-target]", visible: :all

    source = <<~'RUBY'
      vstack(alignment: :leading, spacing: 8) do
        text("Hello #{data[:profile][:name]}").text_style(:headline)
        if data[:profile][:available]
          badge("Available", tone: :success)
        end
      end
    RUBY
    data_json = <<~JSON
      {
        "profile": { "name": "Ada", "available": true }
      }
    JSON
    find("#playground-source").set(source)
    find("#playground-data").set(data_json)
    click_button "Run on Rails"

    assert_current_path %r{/showcase/playground\?draft=}, url: true
    assert_equal source, find("#playground-source").value
    assert_equal data_json, find("#playground-data").value
    within_frame("playground-preview") do
      assert_text "Hello Ada"
      assert_text "Available"
      assert_no_selector "script"
    end

    find("#playground-diagnostics-panel > summary").click
    within "#playground-diagnostics" do
      assert_text "No diagnostics"
    end

    find("#playground-data-inspector-panel > summary").click
    parsed_data = JSON.parse(find("#playground-data-inspector").value)
    assert_equal "Ada", parsed_data.dig("profile", "name")
    assert_equal true, parsed_data.dig("profile", "available")

    assert_no_page_errors
    assert_no_console_errors
  end

  test "shows compiler diagnostics and recovers on the next server run" do
    visit showcase_playground_path

    find("#playground-source").set("vstack do\n  text(\"Broken\")")
    click_button "Run on Rails"

    assert_selector "#playground-diagnostics-panel[open]"
    within "#playground-diagnostics" do
      assert_text(/syntax|parse|unexpected|end/i)
    end
    broken_preview_url = find("#playground-preview")[:src]
    visit broken_preview_url
    assert_text "Preview unavailable"
    assert_text(/syntax|parse|unexpected|end/i)

    visit showcase_playground_path
    find("#playground-source").set('vstack { text("Recovered preview") }')
    find("#playground-data").set("{}")
    click_button "Run on Rails"

    assert_current_path %r{/showcase/playground\?draft=}, url: true
    recovered_preview_url = find("#playground-preview")[:src]
    visit recovered_preview_url
    assert_text "Recovered preview"
    assert_no_text "Preview unavailable"

    visit showcase_playground_path
    assert_no_selector "#playground-diagnostics-panel[open]"

    assert_no_page_errors
    assert_no_console_errors
  end

  test "selects bundled examples and inspects both IR stages without JavaScript" do
    visit showcase_playground_path

    click_link "Mission readiness"

    assert_current_path showcase_playground_path(example: "mission-readiness")
    assert_equal Showcase::Playground::Examples::MISSION_SOURCE, find("#playground-source").value
    assert_equal Showcase::Playground::Examples::MISSION_DATA, find("#playground-data").value
    within_frame("playground-preview") do
      assert_text "Atlas VII"
      assert_text "GO FOR LAUNCH"
    end

    find("#playground-ir-panel > summary").click
    authoring_ir = JSON.parse(find("#playground-authoring-ir").value)
    render_ir = JSON.parse(find("#playground-render-ir").value)
    assert_equal Showcase::Playground::IntermediateRepresentation::SCHEMA, authoring_ir.fetch("schema")
    assert_equal SwiftUIRails::RenderIR::SCHEMA, render_ir.fetch("schema")
    assert_equal "view", authoring_ir.dig("root", "type")
    assert_equal "fragment", render_ir.dig("root", "kind")
    assert_text(/Lowering ready.*authoring nodes.*RenderIR nodes/)

    assert_no_page_errors
    assert_no_console_errors
  end
end
