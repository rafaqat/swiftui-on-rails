# frozen_string_literal: true

class ProductFilterComponent < SwiftUIRails::Component::Base
  prop :current_filters, type: Hash, default: {}
  prop :filter_options, type: Hash, required: true
  prop :products_path, type: String, required: true, validate: :url
  
  swift_ui do
    form(
      action: products_path,
      method: :get,
      data: {
        turbo_frame: "products",
        turbo_action: "advance"
      }
    ) do
      vstack(spacing: 4) do
        text("Filter Products").font_size("lg").font_weight("semibold").margin_bottom(4)
        
        # Each filter type gets its own select field
        filter_options.each do |filter_type, options|
          vstack(spacing: 2) do
            label(filter_type.to_s.humanize, for: "filter_#{filter_type}")
              .text_sm
              .font_weight("medium")
              .text_color("gray-700")
            
            select(
              name: "filters[#{ERB::Util.html_escape(filter_type)}]",
              id: "filter_#{ERB::Util.html_escape(filter_type)}",
              class: "w-full rounded-md border-gray-300"
            ) do
              option("", "All #{filter_type.to_s.pluralize.humanize}")
              options.each do |option_value, option_label|
                option(
                  option_value,
                  option_label,
                  selected: current_filters[filter_type] == option_value
                )
              end
            end
          end
        end
        
        # Keep an explicit submit button for progressive enhancement.
        button("Apply Filters", type: "submit")
          .button_style(:primary)
          .margin_top(4)
          .w_full
      end
    end
  end
end
