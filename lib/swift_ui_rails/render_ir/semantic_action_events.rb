# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # The complete event vocabulary that may invoke a Ruby component action.
    # Keep this smaller than the runtime's full delegated event list: browser
    # behaviors also observe transport-only events which are not application
    # action surfaces.
    module SemanticActionEvents
      NATIVE = %w[
        click dblclick
        mousedown mouseup mouseover mouseout mousemove
        pointerdown pointerup pointermove pointercancel
        keydown keyup submit change input focusin focusout
        load error dragstart dragover drop dragend toggle cancel close
      ].freeze

      FRAMEWORK = %w[
        swift-ui-appear swift-ui-disappear swift-ui-long-press
        swift-ui-drag-end swift-ui-key-press
      ].freeze

      ALL = (NATIVE + FRAMEWORK).freeze

      module_function

      def include?(event_name)
        ALL.include?(event_name.to_s)
      end
    end
  end
end
