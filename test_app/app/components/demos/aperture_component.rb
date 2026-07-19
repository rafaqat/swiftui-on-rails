# frozen_string_literal: true

module Demos
  # Aperture: a masonry photo gallery. Tags and the presented photo are URL
  # state. The semantic sheet renders the selected image on the server and
  # preserves ordinary previous, next, and dismiss destinations.
  class ApertureComponent < ApplicationComponent
    prop :photos, type: Array, required: true
    prop :active_tag, type: String, default: ""
    prop :open_index, type: Integer, default: nil

    swift_ui do
      component = @component

      div do
        vstack(spacing: 16, alignment: :start) do
          hstack(spacing: 8, alignment: :center) do
            tag_chip("All photos", "", component.active_tag.empty?)
            Demos::ApertureGallery.tags.each do |tag|
              tag_chip(tag.capitalize, tag, component.active_tag == tag)
            end
          end

          grid(columns: 3, spacing: 16, masonry: true) do
            component.photos.each_with_index do |photo, index|
              gallery_tile(photo, index)
            end
          end
        end

        lightbox_sheet if component.open_photo
      end
    end

    def open_photo
      return nil unless open_index

      photos[open_index]
    end

    def tag_chip(label, tag, active)
      href = tag.empty? ? helpers.demos_aperture_path : helpers.demos_aperture_path(tag: tag)
      chip = a(label, href: href)
        .tw(
          "rounded-full px-4 py-2 text-sm font-black transition " +
          (active ? "bg-slate-950 text-white" : "bg-white text-slate-600 ring-1 ring-slate-900/10 hover:bg-slate-100")
        )
      chip.attr("aria-current", "page") if active
      chip
    end

    def gallery_tile(photo, index)
      a(
        href: helpers.demos_aperture_path(tag: active_tag.presence, photo: photo.id),
        data: { aperture_photo_index: index },
        aria: { label: "Open #{photo.title}" }
      ) do
        div do
          async_image(
            helpers.image_path(photo.file),
            alt: photo.title,
            image_class: "w-full rounded-2xl"
          )
          hstack(spacing: 8, alignment: :center) do
            text(photo.title).tw("text-sm font-black text-slate-950")
            spacer
            span("##{photo.tag}").tw("text-xs font-black text-slate-400")
          end.tw("px-1 pt-2")
        end
      end.tw("group mb-4 block break-inside-avoid overflow-hidden rounded-2xl bg-white p-2 shadow ring-1 ring-slate-900/10 transition hover:-translate-y-0.5 hover:shadow-xl")
    end

    def lightbox_sheet
      photo = open_photo

      sheet(
        photo.title,
        presented: true,
        id: "aperture-photo",
        dismiss_path: helpers.demos_aperture_path(tag: active_tag.presence)
      ) do
        vstack(spacing: 8, alignment: :center) do
          async_image(helpers.image_path(photo.file), alt: photo.title)
            .tw("max-h-[70vh] rounded-2xl")
          hstack(spacing: 12, alignment: :center) do
            if previous_photo
              a(href: photo_path(previous_photo), aria: { label: "Previous photo" }) do
                icon("chevron_left", size: 18)
              end.tw("rounded-full bg-slate-100 px-4 py-2 text-slate-700")
            end

            p(photo.title)
              .tw("text-sm font-black text-slate-950")

            if next_photo
              a(href: photo_path(next_photo), aria: { label: "Next photo" }) do
                icon("chevron_right", size: 18)
              end.tw("rounded-full bg-slate-100 px-4 py-2 text-slate-700")
            end
          end
        end
      end.tw("rounded-3xl bg-white p-6")
    end

    def previous_photo
      return nil unless open_index&.positive?

      photos[open_index - 1]
    end

    def next_photo
      return nil unless open_index && open_index < photos.length - 1

      photos[open_index + 1]
    end

    def photo_path(photo)
      helpers.demos_aperture_path(tag: active_tag.presence, photo: photo.id)
    end
  end
end
