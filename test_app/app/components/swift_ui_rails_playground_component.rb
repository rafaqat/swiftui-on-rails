# frozen_string_literal: true

require "json"

# The Playground is the framework's dogfood application: its complete UI is
# authored with SwiftUI Rails and every mutation is an ordinary Rails round
# trip. The browser owns only native form, link, disclosure, and iframe
# behaviour; there is no application-side JavaScript model to keep in sync.
class SwiftUiRailsPlaygroundComponent < SwiftUIRails::Component::Base
  IR_DISPLAY_BYTES = 64.kilobytes
  UNSAFE_APPLICATION_PATH_CHARACTERS = /[\\\x00-\x20\x7f]/

  prop :examples, type: Array, required: true
  prop :selected_example, type: Showcase::Playground::Examples::Example, required: true
  prop :initial_result, type: Showcase::Playground::Result, required: true
  prop :compile_url, type: String, required: true
  prop :run_url, type: String, default: nil
  prop :show_url, type: String, default: nil
  prop :preview_url, type: String, default: nil
  prop :source, type: String, default: nil
  prop :data_json, type: String, default: nil
  prop :assist_url, type: String, default: nil
  prop :assistant_available, type: [ TrueClass, FalseClass ], default: false
  prop :language_url, type: String, default: nil
  prop :verify_url, type: String, default: nil
  prop :reliability_url, type: String, default: nil

  swift_ui do
    vstack(
      spacing: 0,
      id: "swift-rails-playground",
      data: { swift_ui_theme: "dark", playground_mode: "server-round-trip" }
    )
      .appearance(:playground_window)
      .background_style(:canvas)
      .foreground_style(:primary) do
        vstack(spacing: 0)
          .appearance(:playground_shell) do
            playground_toolbar

            playground_workbench

            playground_debug_area
            playground_status_bar
          end
      end
  end

  def resolved_run_url
    run_url || "/showcase/playground/run"
  end

  def resolved_show_url
    show_url || "/showcase/playground"
  end

  private

  def validate_props!
    super

    unless examples.all? { |example| example.is_a?(Showcase::Playground::Examples::Example) }
      raise TypeError, "examples must contain playground examples"
    end
    unless examples.include?(selected_example)
      raise ArgumentError, "selected_example must belong to examples"
    end

    endpoint_names = %i[
      compile_url run_url show_url preview_url assist_url language_url verify_url
      reliability_url
    ]
    endpoint_names.each do |name|
      value = public_send(name)
      next if value.nil? || application_relative_url?(value)

      raise ArgumentError, "#{name} must be an application-relative path"
    end
  end

  def application_relative_url?(value)
    value.is_a?(String) && value.start_with?("/") &&
      !value.start_with?("//") && !value.match?(UNSAFE_APPLICATION_PATH_CHARACTERS)
  end

  def editor_source
    source.nil? ? selected_example.source.to_s : source
  end

  def editor_data_json
    data_json.nil? ? selected_example.data_json.to_s : data_json
  end

  def playground_workbench
    workbench = secure_form(
      action: resolved_run_url,
      method: :post,
      turbo: false,
      id: "playground-run-form",
      data: { turbo: false }
    ) do
      input(type: "hidden", name: "example", value: selected_example.id)
      playground_navigator
      playground_editor
      playground_canvas
    end

    workbench.appearance(:playground_workbench)
  end

  def playground_toolbar
    toolbar_view = toolbar(label: "Playground toolbar", overflow: false) do
      hstack(spacing: 6)
        .accessibility_hidden
        .appearance(:playground_window_controls) do
          icon("circle", size: 12).foreground_style(:danger)
          icon("circle", size: 12).foreground_style(:warning)
          icon("circle", size: 12).foreground_style(:success)
        end

      hstack(spacing: 8)
        .appearance(:playground_brand) do
          text("SR")
            .appearance(:playground_brand_mark)
            .background_style(:accent)
            .foreground_style(:on_accent)
            .font(:caption2)
          vstack(alignment: :leading, spacing: 0)
            .appearance(:playground_brand_copy) do
              text("SwiftUI Rails Playground")
                .appearance(:playground_truncated_text)
                .font(:caption)
              text("Rails-owned source → IR → HTML")
                .appearance(:playground_truncated_text)
                .font(:caption2)
                .foreground_style(:secondary)
            end
        end

      divider.appearance(:playground_toolbar_divider)

      text(selected_example.name)
        .appearance(:playground_picker)
        .background_style(:surface)
        .foreground_style(:primary)
        .font(:caption)

      button(
        id: "playground-run",
        type: "submit",
        form: "playground-run-form",
        title: "Send source and fixture data to the Rails compiler"
      )
        .appearance(:playground_run_button)
        .button_style(:bordered_prominent)
        .button_size(:small)
        .background_style(:accent)
        .foreground_style(:on_accent)
        .font(:caption) do
          icon("play", size: 12)
          text("Run on Rails")
        end

      spacer

      link("Language JSON", destination: language_url || "#")
        .appearance(:playground_toolbar_button)
        .font(:caption2)
    end

    toolbar_view.appearance(:playground_toolbar)
  end

  def playground_navigator
    scroll_view(aria: { label: "Playground examples" })
      .appearance(:playground_navigator)
      .background_style(:surface) do
        hstack(spacing: 8)
          .appearance(:playground_panel_header) do
            text("Navigator")
              .appearance(:playground_section_label)
              .font(:caption2)
            spacer
            text("#{examples.length} examples")
              .appearance(:playground_count)
              .text_style(:caption)
          end

        vstack(alignment: :stretch, spacing: 4)
          .appearance(:playground_navigator_content) do
            text("Playgrounds")
              .appearance(:playground_section_label)
              .text_style(:metadata)

            vstack(alignment: :stretch, spacing: 4)
              .appearance(:playground_example_list) do
                examples.each { |example| playground_example_link(example) }
              end

            divider.appearance(:playground_navigator_divider)

            vstack(alignment: :leading, spacing: 6)
              .appearance(:playground_sandbox)
              .background_style(:muted) do
                text("One cognitive model")
                  .appearance(:playground_section_label)
                  .font(:caption2)
                  .foreground_style(:accent)
                text("Ruby DSL declarations compile to versioned IR. Run submits to Rails; the iframe loads a script-free, same-origin preview.")
                  .text_style(:caption)
              end
          end
      end
  end

  def playground_example_link(example)
    selected = example == selected_example
    link(
      destination: "#{resolved_show_url}?example=#{ERB::Util.url_encode(example.id)}",
      aria: { current: ("page" if selected) }
    )
      .appearance(:playground_example_row) do
        hstack(spacing: 8) do
          icon("square", size: 12).foreground_style(selected ? :accent : :secondary)
          text(example.name)
            .appearance(:playground_truncated_text)
            .font(:caption)
        end
        text(example.description)
          .appearance(:playground_example_description)
          .font(:caption2)
          .foreground_style(:secondary)
      end
  end

  def playground_editor
    section(aria: { label: "Source and fixture editors" })
      .appearance(:playground_editor) do
        hstack(alignment: :center, spacing: 8)
          .appearance(:playground_editor_header) do
            text("◇ View.rb")
              .appearance(:playground_editor_tab)
              .font(:caption)
            text("{ } Data.json")
              .appearance(:playground_editor_tab)
              .font(:caption)
            spacer
            text("Both files submit together")
              .appearance(:playground_active_file)
              .font(:caption2)
              .foreground_style(:secondary)
          end

        playground_editor_panel(
          id: "playground-source-panel",
          content: editor_source,
          editor_id: "playground-source",
          field_name: "source",
          label: "SwiftUI Rails source",
          appearance: :playground_source_editor
        )
        playground_editor_panel(
          id: "playground-data-panel",
          content: editor_data_json,
          editor_id: "playground-data",
          field_name: "data_json",
          label: "Preview fixture JSON",
          appearance: :playground_data_editor
        )
      end
  end

  def playground_editor_panel(id:, content:, editor_id:, field_name:, label:, appearance:)
    hstack(spacing: 0, id: id)
      .appearance(:playground_editor_panel) do
        text(line_numbers(content), aria: { hidden: true })
          .appearance(:playground_editor_gutter)
          .font(:caption)
          .foreground_style(:tertiary)

        textarea(
          content,
          id: editor_id,
          name: field_name,
          aria: { label: label },
          autocomplete: "off",
          autocapitalize: "off",
          spellcheck: false,
          wrap: "off"
        )
          .appearance(appearance)
          .background_style(:surface)
          .foreground_style(:primary)
          .font(:caption)
      end
  end

  def line_numbers(content)
    (1..[ content.lines.count, 1 ].max).to_a.join("\n")
  end

  def playground_canvas
    section(aria: { label: "Canvas preview" })
      .appearance(:playground_canvas) do
        hstack(spacing: 8)
          .appearance(:playground_panel_header) do
            icon("square", size: 12).foreground_style(:accent)
            text("Canvas").font(:caption)
            spacer
            hstack(spacing: 6, role: "status", aria: { live: "polite" })
              .appearance(:playground_compile_status) do
                icon("circle", size: 8, data: { state: initial_result.success? ? "success" : "error" })
                  .appearance(:playground_status_dot)
                text(initial_result.success? ? "Server preview ready" : "Compilation needs attention")
                  .font(:caption2)
                  .foreground_style(initial_result.success? ? :success : :danger)
              end
          end

        scroll_view(tabindex: 0, aria: { label: "Scrollable preview canvas" })
          .appearance(:playground_canvas_surface) do
            vstack(spacing: 0, data: { device: "desktop", zoom: "1" })
              .appearance(:playground_device_frame) do
                web_view(
                  preview_url || :blank,
                  id: "playground-preview",
                  title: "SwiftUI Rails rendered preview",
                  sandbox: [ "allow-same-origin" ],
                  loading: :eager
                ).appearance(:playground_preview_frame)
              end
          end
      end
  end

  def playground_debug_area
    section(aria: { label: "Compiler output" })
      .appearance(:playground_debug_area) do
        hstack(spacing: 10)
          .appearance(:playground_debug_header) do
            text("Compiler")
              .appearance(:playground_debug_tab)
              .font(:caption2)
            text("Diagnostics · Data · IR · Language · Assistant · Metrics")
              .font(:caption2)
              .foreground_style(:secondary)
          end

        scroll_view(id: "playground-debug-panels")
          .appearance(:playground_debug_panel) do
            hstack(alignment: :top, spacing: 10) do
              playground_diagnostics
              playground_data_inspector
              playground_ir_inspector
              playground_language_reference
              playground_assistant_status
            end
          end
      end
  end

  def playground_diagnostics
    disclosure_group("Diagnostics", expanded: !initial_result.success?, id: "playground-diagnostics-panel") do
      vstack(alignment: :stretch, spacing: 4, id: "playground-diagnostics", aria: { live: "polite" })
        .appearance(:playground_diagnostics_list) do
          if initial_result.diagnostics.empty?
            text("No diagnostics. The DSL compiled and lowered successfully.")
              .appearance(:playground_diagnostic_success)
          else
            initial_result.diagnostics.each { |diagnostic| playground_diagnostic(diagnostic) }
          end
        end
    end.appearance(:playground_language_detail)
  end

  def playground_diagnostic(diagnostic)
    severity = diagnostic.fetch("severity", "error")
    vstack(alignment: :leading, spacing: 2, data: { severity: severity })
      .appearance(:playground_diagnostic_row) do
        text("#{severity.upcase} · line #{diagnostic.fetch("line", 1)}")
          .appearance(:playground_diagnostic_location)
        text(diagnostic.fetch("message", "Compilation failed"))
          .appearance(:playground_diagnostic_content)
        text(diagnostic.fetch("code", "diagnostic"))
          .appearance(:playground_diagnostic_code)
      end
  end

  def playground_data_inspector
    disclosure_group("Data inspector", id: "playground-data-inspector-panel") do
      textarea(
        bounded_json(initial_result.data),
        id: "playground-data-inspector",
        rows: 10,
        readonly: true,
        spellcheck: false,
        wrap: "off",
        aria: { label: "Parsed fixture data" }
      )
        .appearance(:playground_assistant_prompt)
        .font(:caption2)
    end.appearance(:playground_language_detail)
  end

  def playground_ir_inspector
    disclosure_group("IR inspector", id: "playground-ir-panel") do
      vstack(alignment: :stretch, spacing: 8, id: "playground-ir-inspector") do
        text(ir_status)
          .font(:caption2)
          .foreground_style(initial_result.success? ? :success : :secondary)
        playground_ir_document("Authoring IR", "playground-authoring-ir", initial_result.ir&.to_h)
        playground_ir_document("Resolved RenderIR", "playground-render-ir", initial_result.render_ir&.to_h)
      end
    end.appearance(:playground_language_detail)
  end

  def playground_ir_document(title, id, document)
    label("#{title} canonical JSON", for_input: id)
      .font(:caption2)
      .foreground_style(:accent)
    textarea(
      document ? bounded_json(document) : "Unavailable until the DSL compiles successfully.",
      id: id,
      rows: 10,
      readonly: true,
      spellcheck: false,
      wrap: "off",
      aria: { label: "#{title} canonical JSON" }
    )
      .appearance(:playground_assistant_prompt)
      .font(:caption2)
  end

  def ir_status
    return "IR unavailable while errors remain." unless initial_result.success?

    authoring_nodes = count_authoring_nodes(initial_result.ir&.to_h)
    render_nodes = initial_result.render_ir&.each_node&.count || 0
    "Lowering ready · #{authoring_nodes} authoring nodes → #{render_nodes} RenderIR nodes"
  end

  def count_authoring_nodes(value)
    case value
    when Hash
      (value.key?("type") ? 1 : 0) + value.values.sum { |child| count_authoring_nodes(child) }
    when Array
      value.sum { |child| count_authoring_nodes(child) }
    else
      0
    end
  end

  def playground_language_reference
    disclosure_group("Language reference", id: "playground-language-panel") do
      vstack(alignment: :leading, spacing: 4)
        .appearance(:playground_language_workspace) do
          text("Language #{Showcase::Playground::LanguageCatalog::VERSION}")
            .font(:caption)
            .foreground_style(:accent)
          text("Builders: #{catalog_names("builders")}")
            .font(:caption2)
          text("Modifiers: #{catalog_names("modifiers")}")
            .font(:caption2)
          link("Open the complete versioned catalogue", destination: language_url || "#")
            .appearance(:playground_toolbar_button)
            .font(:caption2)
          link("Run the fixed reliability corpus", destination: reliability_url || "#")
            .appearance(:playground_toolbar_button)
            .font(:caption2)
        end
    end.appearance(:playground_language_detail)
  end

  def playground_assistant_status
    disclosure_group("Assistant", id: "playground-assistant-panel") do
      vstack(alignment: :leading, spacing: 4)
        .appearance(:playground_assistant_workspace) do
          text(assistant_available ? "Model adapter available" : "No model adapter configured")
            .font(:caption)
            .foreground_style(assistant_available ? :success : :secondary)
          text("The assistant endpoint accepts the compact catalogue, returns DSL only, and runs the same validation and repair pipeline before preview.")
            .font(:caption2)
          text(assist_url || "Assistant endpoint unavailable")
            .font(:caption2)
            .foreground_style(:tertiary)
        end
    end.appearance(:playground_language_detail)
  end

  def catalog_names(section)
    names = Showcase::Playground::LanguageCatalog.to_h.fetch(section).keys.sort
    preview = names.first(18).join(", ")
    names.length > 18 ? "#{preview}, … (#{names.length} total)" : preview
  end

  def bounded_json(value)
    json = JSON.pretty_generate(value)
    return json if json.bytesize <= IR_DISPLAY_BYTES

    # byteslice can cut a multibyte character in half; scrub the invalid tail
    # so the textarea receives valid UTF-8.
    prefix = json.byteslice(0, IR_DISPLAY_BYTES).scrub
    "#{prefix}\n… display truncated at #{IR_DISPLAY_BYTES / 1024} KiB"
  rescue JSON::GeneratorError, TypeError
    "Unavailable"
  end

  def playground_status_bar
    hstack(spacing: 0, aria: { label: "Playground status bar" })
      .appearance(:playground_status_bar)
      .background_style(:accent)
      .foreground_style(:on_accent)
      .font(:caption2) do
        hstack(spacing: 6) do
          icon("check", size: 12)
          text("Restricted DSL · no eval")
        end
        text("Server round trips · no application JavaScript")
          .appearance(:playground_status_badge)
        text(status_summary)
          .appearance(:playground_status_item)
        spacer
        text("Source and fixture remain Rails-owned")
          .appearance(:playground_status_item)
      end
  end

  def status_summary
    stats = initial_result.stats
    "#{stats.fetch("source_lines", 0)} lines · #{stats.fetch("render_ir_nodes", 0)} RenderIR nodes · #{stats.fetch("render_ms", 0)} ms"
  end
end
