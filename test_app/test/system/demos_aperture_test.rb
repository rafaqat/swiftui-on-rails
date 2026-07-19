# frozen_string_literal: true

require "application_system_test_case"

# Headline interaction: route-backed thumbnail, previous/next, and dismissal
# links drive the semantic sheet. Filtering logic is covered in the controller
# test.
class DemosApertureTest < ApplicationSystemTestCase
  test "photo sheet opens, traverses, dismisses, and deep-links through Rails routes" do
    visit_demo("aperture")

    find("a[data-aperture-photo-index='0']").click
    assert_current_path(/photo=aurora-veil/, wait: 5)
    within("dialog#aperture-photo[open]") do
      assert_text "Aurora Veil"
      find("a[aria-label='Next photo']").click
    end

    assert_current_path(/photo=harbor-dusk/, wait: 5)
    within("dialog#aperture-photo[open]") do
      assert_text "Harbor Dusk"
      find("a.swift-ui-dialog-close").click
    end
    assert_no_selector "dialog#aperture-photo[open]"

    visit demos_aperture_path(photo: "tidal-glass")
    within("dialog#aperture-photo[open]") do
      assert_text "Tidal Glass"
    end

    assert_demo_healthy
  end
end
