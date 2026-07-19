# frozen_string_literal: true

class SimpleCardComponent < SwiftUIRails::Component::Base
  renders_one :header
  renders_one :footer
  
  prop :variant, type: Symbol, default: :elevated
  prop :padding, type: Symbol, default: :md
  
  VARIANT_CLASSES = {
    elevated: "shadow-md",
    outlined: "border border-gray-200",
    filled: "bg-gray-50"
  }.freeze
  
  PADDING_CLASSES = {
    sm: "p-4",
    md: "p-6",
    lg: "p-8"
  }.freeze
  
  swift_ui do
    comp = @component

    div.tw(card_classes) do
      # Header
      if comp.header?
        div.pb(4).mb(4).border_b.border_color("gray-200") do
          comp.header
        end
      end
      
      # Content (from block)
      div do
        comp.content
      end
      
      # Footer
      if comp.footer?
        div.pt(4).mt(4).border_t.border_color("gray-200") do
          comp.footer
        end
      end
    end
  end
  
  private
  
  def card_classes
    base = "bg-white rounded-lg"
    variant_class = VARIANT_CLASSES[variant] || VARIANT_CLASSES[:elevated]
    padding_class = PADDING_CLASSES[padding] || PADDING_CLASSES[:md]
    
    [base, variant_class, padding_class].compact.join(" ")
  end
end
