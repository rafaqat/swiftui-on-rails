# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module SwiftUIRails
  module RenderIR
    # Request-local values that must never cross the immutable RenderIR
    # boundary. RenderIR contains only opaque identifiers; rendered
    # ViewComponent buffers and other trusted capabilities live here for the
    # duration of one render.
    class CapabilityRegistry
      class MissingCapability < SwiftUIRails::RenderIR::Error; end

      FINGERPRINT_KEY = SecureRandom.random_bytes(32).freeze
      private_constant :FINGERPRINT_KEY

      def initialize
        @values = {}
        @sequences = Hash.new(0)
      end

      def register(kind, value)
        normalized_kind = normalize_kind(kind)
        fingerprint = capability_fingerprint(normalized_kind, value)
        sequence_key = [normalized_kind, fingerprint]
        @sequences[sequence_key] += 1
        identifier = "#{normalized_kind}:#{fingerprint}:#{@sequences.fetch(sequence_key)}".freeze
        @values[identifier] = [normalized_kind, value].freeze
        identifier
      end

      def fetch(identifier, kind: nil)
        entry = @values.fetch(identifier.to_s) do
          raise MissingCapability.new(
            "RenderIR capability `#{identifier}` is not available in this render.",
            path: '$.capabilities'
          )
        end

        expected_kind = kind && normalize_kind(kind)
        if expected_kind && entry.first != expected_kind
          raise MissingCapability.new(
            "RenderIR capability `#{identifier}` is #{entry.first}, not #{expected_kind}.",
            path: '$.capabilities'
          )
        end

        entry.last
      end

      def include?(identifier, kind: nil)
        entry = @values[identifier.to_s]
        return false unless entry

        kind.nil? || entry.first == normalize_kind(kind)
      end

      def count(kind = nil)
        return @values.length unless kind

        normalized_kind = normalize_kind(kind)
        @values.count { |_identifier, entry| entry.first == normalized_kind }
      end

      private

      # A capability value never enters RenderIR. A process-keyed fingerprint
      # does, so different trusted fragments cannot compare equal while an IR
      # dump cannot be used as a dictionary oracle for secret HTML values.
      def capability_fingerprint(kind, value)
        payload = "#{kind}\0#{value.class.name}\0#{value}"
        OpenSSL::HMAC.hexdigest('SHA256', FINGERPRINT_KEY, payload).first(24)
      end

      def normalize_kind(kind)
        value = kind.to_s
        raise ArgumentError, 'capability kind must be a lowercase identifier' unless value.match?(/\A[a-z][a-z0-9_]*\z/)

        value
      end
    end
  end
end
