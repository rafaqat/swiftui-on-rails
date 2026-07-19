# frozen_string_literal: true

module SwiftUIRails
  module RenderIR
    # Enforces the narrow, sandboxed WebView contract for resolved iframe nodes.
    class IframePolicy
      SANDBOX_TOKENS = %w[
        allow-downloads allow-forms allow-modals allow-orientation-lock
        allow-pointer-lock allow-popups allow-popups-to-escape-sandbox
        allow-presentation allow-same-origin allow-scripts allow-storage-access-by-user-activation
        allow-top-navigation allow-top-navigation-by-user-activation
      ].freeze

      def self.validate!(pairs, path)
        attributes = pairs.to_h { |name, value| [name.downcase, ValueCodec.decode(value)] }
        validate_title!(attributes, path)
        validate_source!(attributes, path)
        validate_sandbox!(attributes.fetch('sandbox'), path)
      end

      def self.validate_title!(attributes, path)
        return if attributes['title'].instance_of?(String) && !attributes['title'].strip.empty?

        invalid!('RenderIR iframe requires a non-empty title.', path)
      end
      private_class_method :validate_title!

      def self.validate_source!(attributes, path)
        return if attributes['src'].instance_of?(String) && attributes.key?('sandbox')

        invalid!('RenderIR iframe requires a safe src and sandbox.', path)
      end
      private_class_method :validate_source!

      def self.validate_sandbox!(value, path)
        tokens = value.to_s.split
        invalid!('RenderIR iframe sandbox contains an unsupported token.', path) if (tokens - SANDBOX_TOKENS).any?
        return unless tokens.include?('allow-scripts') && tokens.include?('allow-same-origin')

        invalid!('RenderIR iframe sandbox cannot escape its origin boundary.', path)
      end
      private_class_method :validate_sandbox!

      def self.invalid!(message, path)
        raise InvalidStructure.new(message, path: "#{path}.props.attribute_pairs")
      end
      private_class_method :invalid!
    end
  end
end
