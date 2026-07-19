# frozen_string_literal: true

require "test_helper"

module Demos
  class ApertureControllerTest < ActionDispatch::IntegrationTest
    test "renders the full masonry gallery with route-backed photo links" do
      get demos_aperture_path

      assert_response :success
      assert_select "a[data-aperture-photo-index]", count: ApertureGallery::PHOTOS.length
      assert_select "dialog", count: 0
      assert_select "figure.swift-ui-async-image", count: ApertureGallery::PHOTOS.length
    end

    test "tag filtering is URL-driven" do
      get demos_aperture_path(tag: "city")

      city_count = ApertureGallery.filtered("city").length
      assert_select "a[data-aperture-photo-index]", count: city_count
      assert_select "a[aria-current='page']", text: "City"
    end

    test "photo param deep-links the lightbox open" do
      get demos_aperture_path(photo: "cedar-trail")

      assert_select "dialog#aperture-photo[data-sui-dialog]"
      assert_select "dialog#aperture-photo", text: /Cedar Trail/
      assert_select "a[aria-label='Previous photo']"
      assert_select "a[aria-label='Next photo']"
    end

    test "hostile params degrade to the unfiltered gallery" do
      get demos_aperture_path(tag: "<script>", photo: "../../etc")

      assert_response :success
      assert_select "a[data-aperture-photo-index]", count: ApertureGallery::PHOTOS.length
      assert_select "dialog#aperture-photo", count: 0
    end
  end
end
