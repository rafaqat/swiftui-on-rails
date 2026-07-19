# frozen_string_literal: true

module Demos
  # Aperture owns URL-driven media state: ?tag filters the masonry grid and
  # ?photo deep-links the lightbox open on load. Unknown values fall back
  # silently — URLs are user-editable input.
  class ApertureController < BaseController
    def show
      @active_tag = Demos::ApertureGallery.normalize_tag(params[:tag])
      @photos = Demos::ApertureGallery.filtered(@active_tag)
      @open_index = Demos::ApertureGallery.open_index(@photos, params[:photo])
    end
  end
end
