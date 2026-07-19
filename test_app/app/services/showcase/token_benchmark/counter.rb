# frozen_string_literal: true

require "tiktoken_ruby"

module Showcase
  module TokenBenchmark
    # Counts checked-in source with one explicit BPE encoding. Counts are exact
    # for that encoding; they are not provider API usage or universal tokens.
    class Counter
      ENCODING = "o200k_base"
      METHOD = "tiktoken_bpe"

      Count = Struct.new(:bytes, :characters, :lines, :tokens, :files, keyword_init: true) do
        def +(other)
          self.class.new(
            bytes: bytes + other.bytes,
            characters: characters + other.characters,
            lines: lines + other.lines,
            tokens: tokens + other.tokens,
            files: files + other.files
          ).freeze
        end

        def as_json(*)
          to_h
        end
      end

      class << self
        def call(files, **options)
          new(**options).call(files)
        end

        # Apply only language-neutral normalization. The corpus rejects source
        # that is not already conventionally formatted; it is never minified.
        def normalize_source(source)
          text = source.to_s.encode(Encoding::UTF_8)
          raise ArgumentError, "source must be valid UTF-8" unless text.valid_encoding?

          lines = text.gsub(/\r\n?/, "\n").lines(chomp: true).map(&:rstrip)
          "#{lines.join("\n").sub(/\n+\z/, "")}\n"
        end
      end

      attr_reader :encoding_name

      def initialize(encoding_name: ENCODING, encoder: nil)
        @encoding_name = encoding_name.to_s.freeze
        @encoder = encoder || Tiktoken.get_encoding(@encoding_name)
      end

      def call(files)
        entries = Array(files)
        raise ArgumentError, "at least one source file is required" if entries.empty?

        entries.reduce(zero) do |total, file|
          total + count_source(fetch_content(file))
        end
      end

      def metadata
        {
          method: METHOD,
          encoding: encoding_name,
          exact: true,
          implementation: "tiktoken_ruby",
          implementation_version: Gem.loaded_specs.fetch("tiktoken_ruby").version.to_s,
          normalization: "UTF-8, LF line endings, trailing horizontal whitespace removed, one final newline",
          aggregation: "each file content encoded independently; file counts summed",
          provider_api_usage: false
        }.freeze
      end

      private

      def fetch_content(file)
        return file.fetch("content") if file.is_a?(Hash) && file.key?("content")
        return file.fetch(:content) if file.is_a?(Hash) && file.key?(:content)

        raise ArgumentError, "each source file must contain content"
      end

      def count_source(source)
        normalized = self.class.normalize_source(source)
        Count.new(
          bytes: normalized.bytesize,
          characters: normalized.length,
          lines: normalized.lines.count,
          tokens: @encoder.encode(normalized).length,
          files: 1
        ).freeze
      end

      def zero
        Count.new(bytes: 0, characters: 0, lines: 0, tokens: 0, files: 0).freeze
      end
    end
  end
end
