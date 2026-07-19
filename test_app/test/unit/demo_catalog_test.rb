# frozen_string_literal: true

require "test_helper"

# Guards the DemoCatalog so the /demos gallery can never advertise a broken
# card: every route helper must resolve, every story link must point at a
# registered story, and every interaction model must be a known tag.
class DemoCatalogTest < ActiveSupport::TestCase
  test "catalog slugs are unique" do
    slugs = DemoCatalog.entries.map { |entry| entry.fetch(:slug) }
    assert_equal slugs.uniq, slugs
  end

  test "every entry declares a known interaction model" do
    DemoCatalog.entries.each do |entry|
      assert DemoCatalog::INTERACTION_MODELS.key?(entry.fetch(:model)),
             "Demo #{entry[:slug]} has unknown interaction model #{entry[:model].inspect}"
    end
  end

  test "every entry resolves to a routable path" do
    helpers = Rails.application.routes.url_helpers
    DemoCatalog.entries.each do |entry|
      assert helpers.respond_to?(entry.fetch(:route)),
             "Demo #{entry[:slug]} route helper #{entry[:route]} does not exist"
      path = DemoCatalog.path_for(entry, helpers)
      assert path.start_with?("/"), "Demo #{entry[:slug]} resolved an invalid path: #{path.inspect}"
    end
  end

  test "every story link points at a registered story" do
    DemoCatalog.entries.each do |entry|
      story = entry[:story]
      next unless story

      assert StorybookStoryRegistry.fetch(story),
             "Demo #{entry[:slug]} links story #{story}, which is not registered"
    end
  end

  test "every source component resolves inside app/components" do
    DemoCatalog.entries.each do |entry|
      component_name = entry[:source_component]
      next unless component_name

      component_class = component_name.safe_constantize
      assert component_class, "Demo #{entry[:slug]} source_component #{component_name} does not exist"
      assert StorySourceExtractor.component_source(component_class),
             "Demo #{entry[:slug]} source_component #{component_name} is not extractable"
    end
  end

  test "filtered returns only matching demos and ignores unknown models" do
    cable_demos = DemoCatalog.filtered(:cable)
    assert cable_demos.any?
    assert cable_demos.all? { |entry| entry.fetch(:model) == :cable }

    assert_equal DemoCatalog.entries, DemoCatalog.filtered("nonsense")
  end
end
