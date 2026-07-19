# frozen_string_literal: true

class TabNavigationComponent < SwiftUIRails::Component::Base
  prop :tabs, type: Array, required: true  # [{name:, path:}, ...]
  prop :current_tab, type: String, required: true
  prop :turbo_frame, type: String, default: nil
  
  swift_ui do
    nav(role: "tablist", aria: { label: "Tabs" }) do
      div.border_b do
        hstack(spacing: 0) do
          tabs.each_with_index do |tab, index|
            is_current = tab[:name] == current_tab || tab[:id] == current_tab
            
            link(tab[:name], 
                 destination: tab[:path],
                 role: "tab",
                 aria: { 
                   selected: is_current,
                   controls: "tabpanel-#{index}"
                 },
                 data: turbo_frame ? { turbo_frame: turbo_frame, turbo_action: "advance" } : {})
              .inline_block
              .padding_x(6)
              .padding_y(3)
              .background(is_current ? "white" : "transparent")
              .text_color(is_current ? "blue-600" : "gray-700")
              .font_weight(is_current ? "medium" : "normal")
              .hover_text_color(is_current ? "blue-600" : "gray-900")
              .border_b(2)
              .border_color(is_current ? "blue-600" : "transparent")
              .translate_y("px") # Overlap the nav border by one pixel
              .transition
          end
        end
      end
    end
  end
end
