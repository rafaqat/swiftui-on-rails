# frozen_string_literal: true

module TokenBenchmarks
  class ProductCatalogComponent < ApplicationComponent
    prop :store, type: Hash, required: true
    prop :products, type: Array, required: true

    swift_ui do
      component = @component

      vstack(alignment: :leading, spacing: 18) do
        hstack(spacing: 12) do
          text(component.store.fetch("name")).text_style(:title).accessibility_heading(level: 1)
          spacer
          badge("#{component.store.fetch("product_count")} products", tone: :info)
        end

        grid(columns: 2, spacing: 16) do
          component.products.each do |product|
            article(id: "product-#{product.fetch("id")}") do
              vstack(alignment: :leading, spacing: 10) do
                text(product.fetch("name")).text_style(:headline).accessibility_heading(level: 2)
                text(product.fetch("description")).text_style(:supporting)
                hstack(spacing: 8) do
                  text("$#{product.fetch("price")}").text_style(:body)
                  spacer
                  if product.fetch("in_stock")
                    badge("In Stock", tone: :success)
                  else
                    badge("Sold Out", tone: :danger)
                  end
                end
                button("Inspect").button_style(:bordered)
              end
            end
              .padding(5)
              .background_style(:surface)
              .rounded("xl")
              .shadow("sm")
          end
        end
      end
        .padding(6)
        .background_style(:canvas)
        .rounded("2xl")
    end
  end
end
