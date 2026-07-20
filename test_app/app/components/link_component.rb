# frozen_string_literal: true

class LinkComponent < SwiftUIRails::Component::Base
  # Default styling constants
  DEFAULT_TEXT_COLOR = "blue-600"
  DEFAULT_HOVER_COLOR = "blue-800"
  DEFAULT_FONT_WEIGHT = "normal"
  DEFAULT_FONT_SIZE = "base"
  DEFAULT_UNDERLINE = "hover"
  
  # Valid underline options
  UNDERLINE_OPTIONS = %w[none always hover].freeze
  
  prop :text, type: String, default: "Learn More"
  prop :destination, type: String, default: "#"
  prop :target, type: String, default: ""
  prop :text_color, type: String, default: DEFAULT_TEXT_COLOR
  prop :hover_color, type: String, default: DEFAULT_HOVER_COLOR
  prop :underline, type: String, default: DEFAULT_UNDERLINE
  prop :font_weight, type: String, default: DEFAULT_FONT_WEIGHT
  prop :font_size, type: String, default: DEFAULT_FONT_SIZE

  swift_ui do
    # Several prop names (text, target, underline, font_size…) collide with
    # DSL vocabulary — read them through the component capture, per
    # docs/dsl_authoring.md.
    component = @component

    link(component.text, destination: component.destination).tap do |l|
      if component.target.present?
        l.attr("target", component.target)
        # Any target that opens a new browsing context (_blank or a named
        # target) exposes window.opener to the opened page — prevent reverse
        # tabnabbing. Same-frame keywords navigate in place and are exempt.
        unless %w[_self _parent _top].include?(component.target)
          l.attr("rel", "noopener noreferrer")
        end
      end
      l.text_color(component.text_color) if component.text_color != DEFAULT_TEXT_COLOR
      l.hover_text_color(component.hover_color) if component.hover_color != DEFAULT_HOVER_COLOR

      case component.underline
      when "none"
        l.no_underline
      when "always"
        l.underline
      when "hover"
        l.tw("hover:underline")
      end

      l.font_weight(component.font_weight) if component.font_weight != DEFAULT_FONT_WEIGHT
      l.font_size(component.font_size) if component.font_size != DEFAULT_FONT_SIZE
    end
  end
end