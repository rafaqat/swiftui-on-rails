# frozen_string_literal: true

require "json"

module Showcase
  module Playground
    class FixtureParser
      ParseResult = Struct.new(:data, :diagnostics, :value_count, keyword_init: true)
      MAX_NUMBER_MAGNITUDE = LanguageCatalog.types.fetch("number").fetch("maximum_magnitude")

      def self.call(source)
        new(source).call
      end

      def initialize(source)
        @source = source.to_s
        @value_count = 0
      end

      def call
        validate_source!
        DuplicateKeyScanner.call(@source)
        data = JSON.parse(
          @source,
          create_additions: false,
          symbolize_names: false,
          allow_nan: false,
          max_nesting: Limits::DATA_DEPTH
        )
        raise FixtureError.new("data_root", "Test data must be a JSON object.", path: "$") unless data.is_a?(Hash)

        validate_value!(data, path: "$", depth: 1)
        deep_freeze(data)
        ParseResult.new(data: data, diagnostics: [], value_count: @value_count)
      rescue JSON::NestingError
        failed("data_depth", "Test data is nested more than #{Limits::DATA_DEPTH} levels.")
      rescue JSON::ParserError => error
        line, column = json_error_position(error.message)
        failed("data_syntax", "The test data is not valid JSON.", line: line, column: column)
      rescue DuplicateKeyError => error
        failed("data_duplicate_key", "Test data repeats the object key `#{error.key}`.", path: error.path)
      rescue FixtureError => error
        failed(error.code, error.message, path: error.path)
      end

      private

      FixtureError = Class.new(StandardError) do
        attr_reader :code, :path

        def initialize(code, message, path: nil)
          @code = code
          @path = path
          super(message)
        end
      end

      class DuplicateKeyError < StandardError
        attr_reader :key, :path

        def initialize(key, path:)
          @key = key.to_s.freeze
          @path = path.to_s.freeze
          super("duplicate JSON object key")
        end
      end

      # JSON.parse intentionally keeps the last duplicate object key. Scan the
      # bounded source first so fixtures cannot silently change meaning. This is
      # only a structural duplicate detector; JSON.parse remains the syntax and
      # value parser.
      class DuplicateKeyScanner
        WHITESPACE = [ 0x09, 0x0A, 0x0D, 0x20 ].freeze

        def self.call(source, max_depth: Limits::DATA_DEPTH)
          new(source, max_depth: max_depth).call
        end

        def initialize(source, max_depth:)
          @source = source
          @max_depth = max_depth
          @index = 0
        end

        def call
          skip_whitespace
          scan_value("$", 1)
        end

        private

        def scan_value(path, depth)
          skip_whitespace
          return scan_scalar if depth > @max_depth

          case current_byte
          when 0x7B then scan_object(path, depth)
          when 0x5B then scan_array(path, depth)
          when 0x22 then scan_string
          else scan_scalar
          end
        end

        def scan_object(path, depth)
          @index += 1
          keys = {}
          skip_whitespace
          return @index += 1 if current_byte == 0x7D

          loop do
            skip_whitespace
            return unless current_byte == 0x22

            token = scan_string
            return unless token

            key = decode_string(token)
            return unless key

            key_path = child_path(path, key)
            raise DuplicateKeyError.new(key, path: key_path) if keys.key?(key)

            keys[key] = true
            skip_whitespace
            return unless current_byte == 0x3A

            @index += 1
            scan_value(key_path, depth + 1)
            skip_whitespace
            case current_byte
            when 0x2C
              @index += 1
            when 0x7D
              @index += 1
              return
            else
              return
            end
          end
        end

        def scan_array(path, depth)
          @index += 1
          item_index = 0
          skip_whitespace
          return @index += 1 if current_byte == 0x5D

          loop do
            scan_value("#{path}[#{item_index}]", depth + 1)
            item_index += 1
            skip_whitespace
            case current_byte
            when 0x2C
              @index += 1
            when 0x5D
              @index += 1
              return
            else
              return
            end
          end
        end

        def scan_string
          start = @index
          return unless current_byte == 0x22

          @index += 1
          while @index < @source.bytesize
            case current_byte
            when 0x5C
              @index += 2
            when 0x22
              @index += 1
              return @source.byteslice(start, @index - start)
            else
              @index += 1
            end
          end
          nil
        end

        def scan_scalar
          @index += 1 while @index < @source.bytesize && !value_delimiter?(current_byte)
        end

        def decode_string(token)
          JSON.parse(token, create_additions: false, max_nesting: 1)
        rescue JSON::ParserError
          nil
        end

        def child_path(path, key)
          key.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) ? "#{path}.#{key}" : "#{path}[#{key.inspect}]"
        end

        def skip_whitespace
          @index += 1 while WHITESPACE.include?(current_byte)
        end

        def value_delimiter?(byte)
          byte.nil? || WHITESPACE.include?(byte) || [ 0x2C, 0x5D, 0x7D ].include?(byte)
        end

        def current_byte
          @source.getbyte(@index)
        end
      end

      def validate_source!
        if @source.bytesize > Limits::DATA_BYTES
          raise FixtureError.new("data_size", "Test data is limited to #{Limits::DATA_BYTES / 1024} KiB.")
        end
        unless @source.valid_encoding? && !@source.include?("\0")
          raise FixtureError.new("data_encoding", "Test data must be valid UTF-8 without NUL bytes.")
        end
      end

      def validate_value!(value, path:, depth:)
        raise FixtureError.new("data_depth", "Test data is nested too deeply.", path: path) if depth > Limits::DATA_DEPTH

        @value_count += 1
        if @value_count > Limits::DATA_VALUES
          raise FixtureError.new("data_values", "Test data contains more than #{Limits::DATA_VALUES} values.", path: path)
        end

        case value
        when Hash
          if value.length > Limits::DATA_KEYS_PER_OBJECT
            raise FixtureError.new("data_object_size", "An object contains too many keys.", path: path)
          end
          value.each do |key, child|
            if key.include?("\0")
              raise FixtureError.new("data_key_encoding", "Object keys cannot contain NUL characters.", path: path)
            end
            if key.bytesize > Limits::DATA_KEY_BYTES
              raise FixtureError.new("data_key_size", "A key is longer than #{Limits::DATA_KEY_BYTES} bytes.", path: path)
            end
            validate_value!(child, path: "#{path}.#{key}", depth: depth + 1)
          end
        when Array
          if value.length > Limits::DATA_ARRAY_LENGTH
            raise FixtureError.new("data_array_size", "An array contains more than #{Limits::DATA_ARRAY_LENGTH} items.", path: path)
          end
          value.each_with_index { |child, index| validate_value!(child, path: "#{path}[#{index}]", depth: depth + 1) }
        when String
          if value.include?("\0")
            raise FixtureError.new("data_string_encoding", "Strings cannot contain NUL characters.", path: path)
          end
          if value.bytesize > Limits::DATA_STRING_BYTES
            raise FixtureError.new("data_string_size", "A string is longer than #{Limits::DATA_STRING_BYTES / 1024} KiB.", path: path)
          end
        when Float
          unless value.finite? && value.abs <= MAX_NUMBER_MAGNITUDE
            raise FixtureError.new("data_number", "Numbers must be finite and bounded.", path: path)
          end
        when Integer
          if value.abs > MAX_NUMBER_MAGNITUDE
            raise FixtureError.new("data_number", "Numbers must be finite and bounded.", path: path)
          end
        when TrueClass, FalseClass, NilClass
          nil
        else
          raise FixtureError.new("data_type", "Test data contains an unsupported value.", path: path)
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| key.freeze; deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end

      def json_error_position(message)
        match = message.match(/line\s+(\d+)\s+column\s+(\d+)/i)
        [ match&.[](1)&.to_i || 1, match&.[](2)&.to_i || 1 ]
      end

      def failed(code, message, line: 1, column: 1, path: nil)
        ParseResult.new(
          data: {}.freeze,
          value_count: @value_count,
          diagnostics: [ {
            source: "data",
            severity: "error",
            code: code,
            message: message,
            line: line,
            column: column,
            end_line: line,
            end_column: column,
            path: path
          } ]
        )
      end
    end
  end
end
