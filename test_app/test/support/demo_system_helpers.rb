# frozen_string_literal: true

# Shared helpers for demo-page system tests. Keep per-demo system files to a
# single test that exercises the headline interaction; exhaustive state
# coverage belongs in the demo's fast service and controller tests.
module DemoSystemHelpers
  def visit_demo(slug)
    entry = DemoCatalog.fetch(slug)
    raise ArgumentError, "Unknown demo slug: #{slug}" unless entry

    visit DemoCatalog.path_for(entry, Rails.application.routes.url_helpers)
    entry
  end

  # One-call health check used by the gallery smoke test: the page rendered,
  # produced no console errors, and no inline rendering errors.
  def assert_demo_healthy
    assert_selector "body"
    assert_no_page_errors
    assert_no_console_errors
  end
end
