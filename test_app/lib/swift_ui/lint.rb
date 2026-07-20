# frozen_string_literal: true

require "prism"
require "set"
require_relative "lint_component_fixtures"

module SwiftUi
  # Deterministic linter for SwiftUI Rails component and story files — the
  # generate→validate→repair harness. Three passes:
  #
  #   1. Chain check (static): Prism AST walk collecting every modifier
  #      chained off a DSL builder root; unknown modifiers get a
  #      did-you-mean diagnostic with line/column.
  #   2. Render/IR check (dynamic): instantiates every deterministic component
  #      fixture or registered story variant, renders with strict_css enabled,
  #      and validates the resulting versioned RenderIR document. Hallucinated
  #      palette values, unknown icons/tones, invalid IR, and prop violations
  #      surface as domain-phrased errors.
  #   3. CSS check: every class emitted by the render must exist in the
  #      compiled Tailwind build or a framework-owned stylesheet — catching
  #      the silent-JIT trap without rejecting semantic swift-ui-* classes.
  #
  # Diagnostics use the playground compiler's shape:
  #   { severity:, code:, message:, line:, column:, hint: }
  class Lint
    Diagnostic = Struct.new(:severity, :code, :message, :line, :column, :hint, keyword_init: true) do
      def to_h
        super.compact
      end
    end

    TAILWIND_BUILD = "app/assets/builds/tailwind.css"
    FRAMEWORK_STYLESHEETS = [ "app/assets/stylesheets/application.css" ].freeze

    # These classes are stable DOM contracts for progressive enhancement,
    # accessibility queries, or semantic inspection. Their visual behavior is
    # deliberately supplied by native elements, companion utility classes, or
    # styled descendants. Keep this finite: a new hook must be classified here
    # explicitly rather than being hidden by a `swift-ui-*` prefix exemption.
    STRUCTURAL_CLASS_HOOKS = %w[
      swift-ui-alert
      swift-ui-canvas
      swift-ui-chart
      swift-ui-chart__data
      swift-ui-confirmation
      swift-ui-disclosure
      swift-ui-document-create-button
      swift-ui-document-creation
      swift-ui-document-export
      swift-ui-document-file
      swift-ui-document-import
      swift-ui-document-import-label
      swift-ui-document-progress
      swift-ui-document-status
      swift-ui-document-submit
      swift-ui-document-workflow
      swift-ui-gauge
      swift-ui-map
      swift-ui-map__marker
      swift-ui-map__markers
      swift-ui-menu
      swift-ui-progress
      swift-ui-reorder-button
      swift-ui-reorder-content
      swift-ui-reorder-controls
      swift-ui-reorder-down
      swift-ui-reorder-drag-form
      swift-ui-reorder-form
      swift-ui-reorder-item
      swift-ui-reorder-up
      swift-ui-reorderable-grid
      swift-ui-reorderable-list
      swift-ui-swipe-action
      swift-ui-swipe-action-form
      swift-ui-swipe-actions
      swift-ui-swipe-actions-buttons
      swift-ui-swipe-actions-content
      swift-ui-tab-panels
      swift-ui-tab-view
      swift-ui-text-style-body
      swift-ui-text-style-caption
      swift-ui-text-style-headline
      swift-ui-text-style-metadata
      swift-ui-text-style-supporting
      swift-ui-text-style-title
      swift-ui-toolbar--horizontal
    ].to_set.freeze

    def self.call(path)
      new(path).call
    end

    def initialize(path)
      @path = Rails.root.join(path).to_s
      @diagnostics = []
    end

    def call
      unless File.file?(@path)
        return [ Diagnostic.new(severity: "error", code: "file_missing",
                               message: "No such file: #{@path}") ]
      end

      @source = File.read(@path)
      parse_result = Prism.parse(@source)

      with_strict_css do
        syntax_pass(parse_result)
        if parse_result.success?
          chain_pass(parse_result.value)
          render_pass.each { |rendered_html| tailwind_pass(rendered_html) }
        end
      end

      @diagnostics
    end

    private

    # The linter's whole purpose is strict validation — force it on for the
    # duration regardless of environment configuration.
    def with_strict_css
      SwiftUIRails::Security::StrictCSS.with(enabled: true) { yield }
    end

    def add(severity:, code:, message:, line: nil, column: nil, hint: nil)
      @diagnostics << Diagnostic.new(severity: severity, code: code, message: message,
                                     line: line, column: column, hint: hint)
    end

    # ── Pass 1a: syntax ──────────────────────────────────────────────
    def syntax_pass(parse_result)
      parse_result.errors.first(20).each do |error|
        add(severity: "error", code: "syntax", message: error.message,
            line: error.location.start_line, column: error.location.start_column,
            hint: "Fix the Ruby syntax before the DSL can be checked.")
      end
    end

    # ── Pass 1b: modifier chains ─────────────────────────────────────
    def chain_pass(node)
      each_call_node(node) do |call|
        next unless call.receiver.is_a?(Prism::CallNode)

        name = call.name.to_s
        check_literal_value(call, name)
        next unless dsl_rooted?(call)
        next if modifier_names.include?(name)
        next if name.end_with?("=", "?")
        next unless name.match?(/\A[a-z_]+\z/) # operators ([], +, <<) are Ruby
        next if RUBY_CHAIN_ALLOWANCES.include?(name)
        # Plain-Ruby methods (then/tap/freeze/…) are valid on any object.
        next if Object.public_instance_methods.include?(name.to_sym)

        suggestion = spell_checker.correct(name).first
        add(
          severity: "error", code: "unknown_modifier",
          message: "unknown modifier `.#{name}`",
          line: call.location.start_line, column: call.location.start_column,
          hint: suggestion ? "Did you mean `.#{suggestion}`?" : "See SwiftUIRails::DSL::Element public methods for the vocabulary."
        )
      end
    end

    # Modifiers with finite vocabularies are validated statically when their
    # argument is a literal — same StrictCSS checks the runtime uses, so the
    # two can never drift. Dynamic arguments are left to the render pass.
    STATIC_VALUE_CHECKS = lambda do
      strict = SwiftUIRails::Security::StrictCSS
      validator = SwiftUIRails::Security::CSSValidator
      checks = {
        "bg" => ->(v) { strict.check_color!("background color", v) },
        "background" => ->(v) { strict.check_color!("background color", v) unless v.to_s.start_with?("#") },
        "text_color" => ->(v) { strict.check_color!("text color", v) },
        "rounded" => ->(v) { strict.check_allowlist!("rounded size", v, validator::VALID_ROUNDED_WITH_EDGES, allow_blank: true) }
      }
      SwiftUIRails::DSL::Element::STRICT_TEXT_ALLOWLISTS.each do |method_name, allowlist|
        checks[method_name.to_s] = ->(v) { strict.check_allowlist!("value for .#{method_name}", v, allowlist) }
      end
      SwiftUIRails::DSL::Element::SPACING_UTILITIES.each_key do |method_name|
        checks[method_name.to_s] = lambda do |v|
          strict.check_allowlist!("spacing value for .#{method_name}", v, validator::VALID_SPACING)
        end
      end
      checks
    end.call.freeze

    def check_literal_value(call, name)
      checker = STATIC_VALUE_CHECKS[name]
      return unless checker

      argument = call.arguments&.arguments&.first
      value = literal_value(argument)
      return if value.nil?

      checker.call(value)
    rescue ArgumentError => error
      add(severity: "error", code: "invalid_value",
          message: error.message,
          line: argument.location.start_line, column: argument.location.start_column)
    end

    def literal_value(node)
      case node
      when Prism::StringNode then node.unescaped
      when Prism::SymbolNode then node.value
      when Prism::IntegerNode, Prism::FloatNode then node.value
      end
    end

    def each_call_node(node, &block)
      return unless node.is_a?(Prism::Node)

      yield node if node.is_a?(Prism::CallNode)
      node.compact_child_nodes.each { |child| each_call_node(child, &block) }
    end

    # A chain counts as DSL-rooted when walking receivers lands on a bare
    # (receiver-less) call whose name is a DSL builder — text(...), vstack,
    # div... Chains rooted in component helpers or plain Ruby are skipped:
    # conservative, no false positives.
    def dsl_rooted?(call)
      root = call.receiver
      root = root.receiver while root.is_a?(Prism::CallNode) && root.receiver
      root.is_a?(Prism::CallNode) && root.receiver.nil? && builder_names.include?(root.name.to_s)
    end

    # Chains that continue off ordinary Ruby values (state readers,
    # controller/session access, enumerables) — never modifier mistakes.
    RUBY_CHAIN_ALLOWANCES = %w[
      controller params request session view_context helpers
      each each_with_index each_with_object map filter select reject find
      first last sort sort_by uniq flat_map fetch dig keys values join
      to_s to_i to_a to_h to_json to_sym presence present? blank? empty?
    ].to_set.freeze

    def builder_names
      # Element builders only — DSLContext's own surface (view_context,
      # render, capture…) roots ordinary Ruby chains, not DSL chains.
      @builder_names ||= SwiftUIRails::DSL.public_instance_methods(false).map(&:to_s).to_set
    end

    def modifier_names
      @modifier_names ||= (SwiftUIRails::DSL::Element.public_instance_methods -
                           Object.public_instance_methods).map(&:to_s).to_set
    end

    def spell_checker
      @spell_checker ||= DidYouMean::SpellChecker.new(dictionary: modifier_names.to_a)
    end

    # ── Pass 2: render ───────────────────────────────────────────────
    def render_pass
      constant = target_constant
      unless constant
        add(severity: "info", code: "not_renderable",
            message: "No *Component or *Stories class found; dynamic checks do not apply.")
        return []
      end

      render_target(constant)
    rescue StandardError => error
      add(severity: "error", code: "render_failed",
          message: "#{constant}: #{error.class}: #{error.message.to_s.first(300)}")
      []
    end

    def target_constant
      class_names = @source.scan(/^\s*class\s+([A-Z][A-Za-z0-9:]*(?:Component|Stories))\b/).flatten
      return nil if class_names.empty?

      require_dependency @path

      # Rails-style: derive the namespaced constant from the file path when
      # it lives under a conventional root; module-nested files (class Foo
      # inside module Demos) don't carry the namespace on the class line.
      %r{(?:app/components|test/components/stories|app/services)/(.+)\.rb\z}.match(@path) do |match|
        candidate = match[1].camelize
        return candidate.constantize if Object.const_defined?(candidate)
      end

      module_names = @source.scan(/^\s*module\s+([A-Z][A-Za-z0-9]*)\s*$/).flatten
      [ *module_names, class_names.last ].join("::").constantize
    end

    def render_target(constant)
      if constant.name.end_with?("Stories")
        render_story_variants(constant)
      else
        render_component_cases(constant)
      end
    end

    def render_component_cases(constant)
      unless constant < SwiftUIRails::Component::Base
        add(
          severity: "info",
          code: "non_swift_ui_component",
          message: "#{constant} is a plain ViewComponent; RenderIR checks do not apply."
        )
        return []
      end

      if LintComponentFixtures.abstract?(constant)
        add(severity: "info", code: "abstract_component",
            message: "#{constant} is an explicitly registered abstract component.")
        return []
      end

      cases = LintComponentFixtures.cases_for(constant)
      if cases.empty?
        required = LintComponentFixtures.required_props(constant)
        add(
          severity: "error",
          code: "fixture_missing",
          message: "#{constant} has no deterministic lint fixture.",
          hint: "Register a fixture for required props: #{required.join(', ')}."
        )
        return []
      end

      cases.filter_map do |fixture_case|
        component = fixture_case.build(view_context: lint_view_context)
        render_component_instance(component, label: "#{constant} [#{fixture_case.name}]")
      rescue StandardError => error
        add_render_failure("#{constant} [#{fixture_case.name}]", error)
        nil
      end
    end

    def render_component_instance(component, label:)
      html = ApplicationController.render(component, layout: false).to_s
      return nil if error_boundary?(html, label)

      render_ir_pass(component, label: label)
      html
    end

    def render_ir_pass(component, label:)
      unless component.respond_to?(:last_render_ir)
        add(
          severity: "error",
          code: "ir_unavailable",
          message: "#{label} rendered without the RenderIR component contract.",
          hint: "SwiftUI Rails components must render through the resolved RenderIR pipeline."
        )
        return
      end

      document = component.last_render_ir
      unless document.is_a?(SwiftUIRails::RenderIR::Document)
        add(
          severity: "error",
          code: "ir_missing",
          message: "#{label} did not produce a RenderIR document.",
          hint: "Move custom #call HTML into a swift_ui block so it enters the shared renderer."
        )
        return
      end

      SwiftUIRails::RenderIR::Validator.validate!(document)
      round_trip = SwiftUIRails::RenderIR::Document.from_json(document.canonical_json)
      return if round_trip == document && document.each_node.any?

      add(
        severity: "error",
        code: "ir_round_trip",
        message: "#{label} produced RenderIR that does not survive canonical JSON round-trip.",
        hint: "RenderIR may contain only versioned, deeply immutable JSON-native data."
      )
    rescue SwiftUIRails::RenderIR::Error => error
      add(
        severity: "error",
        code: "ir_invalid",
        message: "#{label}: #{error.message}",
        hint: "Invalid RenderIR value at #{error.path}."
      )
    end

    def render_story_variants(constant)
      variants = story_variants(constant)
      if variants.empty?
        add(
          severity: "error",
          code: "story_variants_missing",
          message: "#{constant} has no registered story variants."
        )
        return []
      end

      variants.filter_map do |variant|
        story = constant.new
        result = StoryRenderer.new(story_controller).render_story(
          story,
          variant,
          **story_defaults(constant, variant)
        )
        label = "#{constant}##{variant}"

        if result.is_a?(SwiftUIRails::Component::Base)
          render_component_instance(result, label: label)
        else
          html = ApplicationController.render(result, layout: false).to_s
          error_boundary?(html, label) ? nil : html
        end
      rescue StandardError => error
        add_render_failure("#{constant}##{variant}", error)
        nil
      end
    end

    def story_variants(constant)
      entry = StorybookStoryRegistry.all.find { |candidate| candidate.story_class == constant }
      return entry.variants if entry

      constant.public_instance_methods(false).sort_by do |variant|
        constant.instance_method(variant).source_location&.last || Float::INFINITY
      end
    end

    def story_defaults(constant, variant)
      story = constant.respond_to?(:find_story) ? constant.find_story(variant) : nil
      return {} unless story

      accepted = constant.instance_method(variant).parameters.filter_map do |kind, name|
        name if %i[key keyreq].include?(kind)
      end
      story.controls.each_with_object({}) do |control, params|
        params[control.param] = control.default if accepted.include?(control.param)
      end
    end

    def lint_view_context
      @lint_view_context ||= story_controller.view_context
    end

    def story_controller
      @story_controller ||= begin
        controller = StorybookController.new
        request = ActionDispatch::TestRequest.create
        request.set_header("action_dispatch.routes", Rails.application.routes)
        controller.set_request!(request)
        controller.set_response!(ActionDispatch::TestResponse.new)
        controller
      end
    end

    def error_boundary?(html, label)
      return false unless html.include?("swift-ui-error-boundary")

      message = html[/unknown [^<]{0,220}/] || html[/Error Message:\s*<[^>]*>\s*([^<]{0,220})/, 1] ||
                "component rendered its error boundary"
      add(
        severity: "error",
        code: "render_failed",
        message: "#{label}: #{message.strip}",
        hint: "Rendered with strict_css enabled — the message names the invalid value."
      )
      true
    end

    def add_render_failure(label, error)
      add(
        severity: "error",
        code: "render_failed",
        message: "#{label}: #{error.class}: #{error.message.to_s.first(300)}",
        hint: "Rendered with strict_css enabled — the message names the invalid value."
      )
    end

    # ── Pass 3: compiled Tailwind classes ────────────────────────────
    def tailwind_pass(html)
      return if tailwind_tokens.empty?

      emitted = html.scan(/class="([^"]*)"/).flatten.flat_map(&:split).uniq
      emitted.each do |token|
        next if token.match?(/[A-Z]/) # constant-ish tokens are not Tailwind
        next if STRUCTURAL_CLASS_HOOKS.include?(token)
        next if tailwind_tokens.include?(token)
        next unless missing_css_tokens.add?(token)

        add(severity: "warning", code: "missing_tailwind_class",
            message: "class `#{token}` is not in the compiled CSS sources",
            hint: "Run bin/rails tailwindcss:build, define the class in a framework stylesheet, or use a validated modifier.")
      end
    end

    def missing_css_tokens
      @missing_css_tokens ||= Set.new
    end

    def tailwind_tokens
      @tailwind_tokens ||= begin
        build = Rails.root.join(TAILWIND_BUILD)
        if build.file?
          [ build, *FRAMEWORK_STYLESHEETS.map { |path| Rails.root.join(path) } ]
            .select(&:file?)
            .each_with_object(Set.new) do |stylesheet, tokens|
              stylesheet.read.scan(/\.((?:\\.|[a-zA-Z0-9_-])+)/).flatten.each do |token|
                tokens << token.gsub(/\\(.)/, '\1')
              end
            end
        else
          add(severity: "info", code: "tailwind_build_missing",
              message: "#{TAILWIND_BUILD} not found; Tailwind class check skipped.")
          Set.new
        end
      end
    end
  end
end
