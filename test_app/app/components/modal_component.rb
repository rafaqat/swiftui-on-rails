# frozen_string_literal: true

class ModalComponent < SwiftUIRails::Component::Base
  prop :open, type: [TrueClass, FalseClass], default: false
  prop :title, type: String, required: true
  prop :close_path, type: String, required: true
  prop :size, type: Symbol, default: :md # :sm, :md, :lg, :xl
  
  renders_one :body
  renders_one :footer
  
  swift_ui do
    comp = @component

    if comp.open
      sheet(
        comp.title,
        presented: true,
        id: "modal",
        dismiss_path: comp.close_path,
        dismiss_label: "Close"
      ) do
        vstack(spacing: 0) do
          div.padding(6) do
            comp.body || text("Modal content goes here")
          end

          if comp.footer?
            div.padding(6).border_t.background("gray-50") do
              comp.footer
            end
          end
        end
      end
        .style("width: #{comp.send(:modal_width)}; max-width: calc(100vw - 2rem); max-height: 90vh; overflow-y: auto")
        .background("white")
        .corner_radius("lg")
        .shadow("xl")
    end
  end
  
  private
  
  def modal_width
    case size
    when :sm then "24rem"
    when :lg then "48rem"
    when :xl then "64rem"
    else "32rem" # :md default
    end
  end
end
