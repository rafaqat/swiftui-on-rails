# frozen_string_literal: true

module Demos
  # Shared chrome for per-demo controllers (Demos::FlightplanController etc.).
  # Clones the proven Showcase pattern: session-backed state PORO, Turbo
  # Stream replace of the demo's root frame, HTML redirect fallback, and
  # bounded error messages so exceptions never leak internals.
  class BaseController < ApplicationController
    helper_method :demo_metadata, :demo_source

    private

    # Catalog entry for this controller, resolved by convention from the
    # controller name (Demos::FlightplanController -> "flightplan").
    def demo_metadata
      @demo_metadata ||= DemoCatalog.fetch(controller_name) ||
                         raise(NameError, "No DemoCatalog entry for demo slug #{controller_name.inspect}")
    end

    # [path, source] for the demo's backing component, for the source panel.
    def demo_source
      component_name = demo_metadata[:source_component]
      return unless component_name

      @demo_source ||= StorySourceExtractor.component_source(component_name.safe_constantize)
    end

    def respond_with_demo(component, frame_id:, notice:, anchor: nil)
      persist_demo_state
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(frame_id, component),
            toast_stream(notice, variant: "success")
          ]
        end
        format.html do
          redirect_to demo_location(anchor: anchor), status: :see_other, notice: notice
        end
      end
    end

    def respond_with_demo_error(component, message, frame_id:, anchor: nil)
      persist_demo_state
      safe_message = bounded_error_message(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(frame_id, component),
            toast_stream(safe_message, variant: "error")
          ], status: :unprocessable_entity
        end
        format.html do
          redirect_to demo_location(anchor: anchor), status: :see_other, alert: safe_message
        end
      end
    end

    def toast_stream(message, variant: "info")
      turbo_stream.append("toasts", ToastComponent.new(message: message, variant: variant))
    end

    def demo_location(anchor: nil)
      DemoCatalog.path_for(demo_metadata, self).then do |path|
        anchor ? "#{path}##{anchor}" : path
      end
    end

    # Subclasses that keep session state override this to write it back
    # before responding. The base implementation is a no-op.
    def persist_demo_state; end

    def bounded_error_message(message)
      value = message.to_s
      return "The request could not be completed." unless value.valid_encoding?

      value.first(180).presence || "The request could not be completed."
    end
  end
end
