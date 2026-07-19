# frozen_string_literal: true

require "test_helper"

class CommandPaletteComponentTest < ViewComponent::TestCase
  def test_renders_semantic_popover_and_server_rendered_commands
    render_inline(CommandPaletteComponent.new)

    assert_selector "details#command-palette[data-sui-popover='1']"
    assert_selector "summary", text: "Jump anywhere"
    assert_selector "li[data-command-keywords]",
                    count: CommandPaletteComponent::SAMPLE_COMMANDS.length, visible: :all
  end

  def test_commands_are_plain_links_reachable_without_javascript
    commands = [
      { label: "Ledger", href: "/demos/ledger", section: "Data", keywords: "invoices" }
    ]
    render_inline(CommandPaletteComponent.new(commands: commands))

    assert_selector "a[href='/demos/ledger']", text: "Ledger", visible: :all
  end

  def test_keywords_remain_semantic_search_metadata
    commands = [
      { label: "Flightplan", href: "/demos/flightplan", section: "Boards", keywords: "kanban drag" }
    ]
    render_inline(CommandPaletteComponent.new(commands: commands))

    assert_selector "li[data-command-keywords='kanban drag']", visible: :all
  end
end
