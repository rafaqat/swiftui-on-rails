# frozen_string_literal: true

# Read-only broadcast channel for the server-owned operations showcase.
#
# The showcase is not a SwiftUIRails reactive component, so it intentionally
# has no component snapshot or browser-triggered channel actions. Mutations go
# through the normal CSRF-protected Rails endpoint; this channel only delivers
# broadcasts to holders of the short-lived, dashboard-bound capability.
class ShowcaseOperationsChannel < ApplicationCable::Channel
  def subscribed
    component_id = params[:component_id]&.to_s
    stream_token = params[:stream_token]&.to_s

    unless valid_component_id?(component_id) && valid_stream_token?(stream_token, component_id)
      Rails.logger.error "[SECURITY] Operations WebSocket subscription rejected"
      reject
      return
    end

    stream_for component_id
  end

  private

  def valid_component_id?(component_id)
    component_id.is_a?(String) && component_id.length <= 200 &&
      component_id.match?(/\Aswift-ui-operations-dashboard-\d+\z/)
  end

  def valid_stream_token?(stream_token, component_id)
    authorization_context = SwiftUIRails::Reactive::ReactiveAuthorizationContext.resolve(self)
    SwiftUIRails::Reactive::ReactiveStreamToken.valid_for?(
      stream_token,
      component_id,
      authorization_context: authorization_context
    )
  end
end
