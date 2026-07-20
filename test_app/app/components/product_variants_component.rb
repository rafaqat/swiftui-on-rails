# frozen_string_literal: true

class ProductVariantsComponent < SwiftUIRails::Component::Base
  prop :variants, type: Array, required: true
  prop :selected_variant, type: [Hash, NilClass], default: nil
  prop :on_select, type: Proc, default: nil
  prop :display_style, type: Symbol, default: :auto # :auto, :dropdown, :buttons, :swatches

  state :active_variant, -> { (selected_variant || {}).deep_stringify_keys }, type: Hash
  
  swift_ui do
    create_element(:div, nil, {class: "flex flex-col items-center space-y-2 mt-2"}) do
      variants.group_by { |v| v[:type] }.each do |variant_type, variant_options|
        # Determine display style for this variant type
        style = determine_display_style(variant_type, variant_options)
        
        case style
        when :swatches
          # Color swatches
          hstack(spacing: 1).tw("flex-wrap") do
            variant_options.each do |variant|
              variant_button = button("") # Empty content for color swatch
                .w(6)
                .h(6)
                .rounded("full")
                .border(2)
                .border_color(variant_selected?(variant) ? "gray-900" : "gray-300")
                .tw("ring-2")
                .tw(variant_selected?(variant) ? "ring-gray-900" : "ring-transparent")
                .tw("ring-offset-1")
                .transition
                .tw("duration-200")
                .style("background-color: #{variant[:hex_color] || variant[:value]}")
                .data("variant-data": variant.to_json)
                .attr("title", variant[:label] || variant[:value])
              variant_button.on_click { select_variant(variant) }
            end
          end
          
        when :buttons
          # Size/text buttons
          hstack(spacing: 1).tw("flex-wrap") do
            variant_options.each do |variant|
              btn_attrs = {
                class: "px-3 py-1 text-xs border rounded-md cursor-#{variant[:available] == false ? 'not-allowed' : 'pointer'} opacity-#{variant[:available] == false ? '50' : '100'}"
              }
              
              if variant_selected?(variant)
                btn_attrs[:class] += " bg-gray-900 text-white border-gray-900"
              else
                btn_attrs[:class] += " bg-white text-gray-900 border-#{variant[:available] == false ? 'gray-200' : 'gray-300'}"
              end
              
              if variant[:available] != false
                btn_attrs[:data] = { "variant-data": variant.to_json }
              end

              variant_button = button(variant[:label] || variant[:value], **btn_attrs)
              variant_button.on_click { select_variant(variant) } if variant[:available] != false
            end
          end
          
        when :dropdown
          # Dropdown selector - use buttons for now
          hstack(spacing: 1).tw("flex-wrap") do
            variant_options.each do |variant|
              btn_attrs = {
                class: "px-2 py-1 text-xs border rounded-sm cursor-#{variant[:available] == false ? 'not-allowed' : 'pointer'} opacity-#{variant[:available] == false ? '50' : '100'}"
              }
              
              if variant_selected?(variant)
                btn_attrs[:class] += " bg-gray-900 text-white border-gray-900"
              else
                btn_attrs[:class] += " bg-white text-gray-900 border-#{variant[:available] == false ? 'gray-200' : 'gray-300'}"
              end
              
              if variant[:available] != false
                btn_attrs[:data] = { "variant-data": variant.to_json }
              end

              variant_button = button(variant[:label] || variant[:value], **btn_attrs)
              variant_button.on_click { select_variant(variant) } if variant[:available] != false
            end
          end
        end
      end
    end
  end
  
  def determine_display_style(variant_type, options)
    return display_style unless display_style == :auto
    
    case variant_type.to_s.downcase
    when "color", "colour"
      :swatches
    when "size"
      :buttons
    else
      options.length > 5 ? :dropdown : :buttons
    end
  end
  
  def variant_selected?(variant)
    selected = active_variant.stringify_keys
    candidate = variant.stringify_keys
    return false if selected.empty?

    # Only match on id when both sides actually carry one; otherwise nil == nil
    # would mark every id-less variant as selected. Fall back to type/value.
    if selected["id"].present? && candidate["id"].present?
      selected["id"] == candidate["id"]
    else
      selected["type"] == candidate["type"] && selected["value"] == candidate["value"]
    end
  end

  def select_variant(variant)
    self.active_variant = variant.deep_stringify_keys
    on_select.call(variant) if on_select.respond_to?(:call)
  end
end
