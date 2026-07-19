# frozen_string_literal: true

require "test_helper"
require "prism"

class ShowcaseApplicationShellComponentTest < ViewComponent::TestCase
  COMPONENT_SOURCE_PATH = Rails.root.join("app/components/showcase_application_shell_component.rb")

  test "renders shared showcase chrome entirely through SwiftUI Rails" do
    render_inline(
      ShowcaseApplicationShellComponent.new(
        page_content: '<p id="page-body">Page body</p>'.html_safe,
        current_path: "/showcase/playground"
      )
    )

    assert_selector "[data-swift-ui-appearance='showcase-application-shell']"
    assert_selector "nav[aria-label='Primary navigation'].swift-ui-navigation-stack"
    assert_selector "a[href='/showcase/playground'][aria-current='page']", text: "Playground"
    assert_selector "main[data-swift-ui-appearance='showcase-page-content'] #page-body", text: "Page body"
  end

  test "contains no raw presentation classes or Tailwind escape hatches" do
    source = COMPONENT_SOURCE_PATH.read
    parsed = Prism.parse(source)
    assert_empty parsed.errors

    nodes = [ parsed.value ]
    violations = []
    until nodes.empty?
      node = nodes.pop
      if node.is_a?(Prism::AssocNode) &&
          node.key.is_a?(Prism::SymbolNode) &&
          node.key.unescaped == "class"
        violations << "line #{node.location.start_line}: #{node.location.slice}"
      elsif node.is_a?(Prism::CallNode) && node.name == :tw
        violations << "line #{node.location.start_line}: #{node.location.slice}"
      end
      nodes.concat(node.compact_child_nodes)
    end

    assert_empty violations, violations.join("\n")
  end

  test "rejects non-application paths" do
    assert_raises(ArgumentError) do
      render_inline(ShowcaseApplicationShellComponent.new(page_content: "body", current_path: "https://attacker.test"))
    end
    assert_raises(ArgumentError) do
      render_inline(ShowcaseApplicationShellComponent.new(page_content: "body", current_path: "//attacker.test"))
    end
  end
end
