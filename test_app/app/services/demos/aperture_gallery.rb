# frozen_string_literal: true

module Demos
  # Fixed photo metadata for the Aperture gallery. Assets are bundled SVGs,
  # so the demo works offline and identically in every environment.
  class ApertureGallery
    Photo = Data.define(:id, :title, :tag, :file)

    PHOTOS = [
      Photo.new(id: "aurora-veil", title: "Aurora Veil", tag: "sky", file: "aperture/photo-01.svg"),
      Photo.new(id: "harbor-dusk", title: "Harbor Dusk", tag: "city", file: "aperture/photo-02.svg"),
      Photo.new(id: "cedar-trail", title: "Cedar Trail", tag: "forest", file: "aperture/photo-03.svg"),
      Photo.new(id: "neon-district", title: "Neon District", tag: "city", file: "aperture/photo-04.svg"),
      Photo.new(id: "tidal-glass", title: "Tidal Glass", tag: "ocean", file: "aperture/photo-05.svg"),
      Photo.new(id: "polar-bloom", title: "Polar Bloom", tag: "sky", file: "aperture/photo-06.svg"),
      Photo.new(id: "skyline-grid", title: "Skyline Grid", tag: "city", file: "aperture/photo-07.svg"),
      Photo.new(id: "ember-coast", title: "Ember Coast", tag: "ocean", file: "aperture/photo-08.svg"),
      Photo.new(id: "moss-hollow", title: "Moss Hollow", tag: "forest", file: "aperture/photo-09.svg"),
      Photo.new(id: "violet-reef", title: "Violet Reef", tag: "ocean", file: "aperture/photo-10.svg"),
      Photo.new(id: "salt-flats", title: "Salt Flats", tag: "sky", file: "aperture/photo-11.svg"),
      Photo.new(id: "night-market", title: "Night Market", tag: "city", file: "aperture/photo-12.svg")
    ].freeze

    class << self
      def tags
        PHOTOS.map(&:tag).uniq.sort
      end

      def filtered(tag)
        return PHOTOS unless tags.include?(tag.to_s)

        PHOTOS.select { |photo| photo.tag == tag.to_s }
      end

      def normalize_tag(tag)
        tags.include?(tag.to_s) ? tag.to_s : ""
      end

      # Index of the deep-linked photo within the filtered set, or nil.
      def open_index(photos, photo_id)
        photos.index { |photo| photo.id == photo_id.to_s }
      end
    end
  end
end
