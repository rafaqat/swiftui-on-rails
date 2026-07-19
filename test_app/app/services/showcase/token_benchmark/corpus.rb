# frozen_string_literal: true

require "digest"
require "json"
require "shellwords"
require "yaml"

module Showcase
  module TokenBenchmark
    # Loads a strict, paired corpus. Every case has one shared behavior contract
    # and fixture, then exactly one React Rails and one SwiftUI Rails reference.
    class Corpus
      SCHEMA_VERSION = "1.0.0"
      IMPLEMENTATIONS = %w[react_rails swift_ui_rails].freeze
      SCOPES = %w[view_source production_support].freeze
      DEFAULT_PATH = Rails.root.join("config/token_benchmarks/react_vs_swift_ui_rails.yml")
      MAX_CASES = 20
      MAX_FILES_PER_SCOPE = 24
      MAX_FILE_BYTES = 128.kilobytes

      class Invalid < StandardError; end

      class << self
        def default
          load(DEFAULT_PATH)
        end

        def load(path)
          source = File.binread(path)
          DuplicateKeyScanner.call(source)
          document = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
          new(document, source_digest: Digest::SHA256.hexdigest(source))
        rescue Psych::Exception => error
          raise Invalid, "invalid benchmark YAML: #{error.message}"
        end
      end

      attr_reader :source_digest

      class DuplicateKeyScanner
        def self.call(source)
          new(source).call
        end

        def initialize(source)
          @source = source
        end

        def call
          walk(Psych.parse_stream(@source), "$")
        end

        private

        def walk(node, path)
          case node
          when Psych::Nodes::Mapping
            keys = {}
            node.children.each_slice(2).with_index do |(key_node, value_node), index|
              key = key_node.is_a?(Psych::Nodes::Scalar) ? key_node.value : "<complex-key-#{index}>"
              raise Invalid, "duplicate benchmark key #{key.inspect} at #{path}" if keys.key?(key)

              keys[key] = true
              walk(value_node, "#{path}.#{key}")
            end
          when Psych::Nodes::Sequence
            node.children.each_with_index { |child, index| walk(child, "#{path}[#{index}]") }
          else
            Array(node.children).each { |child| walk(child, path) } if node.respond_to?(:children)
          end
        end
      end

      def initialize(document, source_digest: nil)
        @document = validate!(document)
        @source_digest = (source_digest || Digest::SHA256.hexdigest(JSON.generate(document))).freeze
        deep_freeze(@document)
      end

      def corpus_version
        @document.fetch("corpus_version")
      end

      def methodology
        @document.fetch("methodology")
      end

      def cases
        @document.fetch("cases")
      end

      private

      def validate!(document)
        require_hash!(document, "root")
        require_exact_keys!(document, %w[schema_version corpus_version methodology cases], "root")
        invalid!("unsupported schema_version") unless document.fetch("schema_version") == SCHEMA_VERSION
        require_version!(document.fetch("corpus_version"), "corpus_version")
        validate_methodology!(document.fetch("methodology"))
        validate_cases!(document.fetch("cases"))
        document
      end

      def validate_methodology!(methodology)
        path = "methodology"
        require_hash!(methodology, path)
        require_exact_keys!(
          methodology,
          %w[track comparison_unit scopes shared_inputs exclusions claim_boundary],
          path
        )
        require_text!(methodology.fetch("track"), "#{path}.track")
        require_text!(methodology.fetch("comparison_unit"), "#{path}.comparison_unit")
        require_hash!(methodology.fetch("scopes"), "#{path}.scopes")
        require_exact_keys!(
          methodology.fetch("scopes"),
          %w[view_source authored_production_closure],
          "#{path}.scopes"
        )
        methodology.fetch("scopes").each do |name, description|
          require_text!(description, "#{path}.scopes.#{name}")
        end
        require_text!(methodology.fetch("shared_inputs"), "#{path}.shared_inputs")
        require_string_array!(methodology.fetch("exclusions"), "#{path}.exclusions")
        require_text!(methodology.fetch("claim_boundary"), "#{path}.claim_boundary")
      end

      def validate_cases!(cases)
        invalid!("cases must be a non-empty array") unless cases.is_a?(Array) && cases.any?
        invalid!("cases exceeds #{MAX_CASES}") if cases.length > MAX_CASES

        ids = cases.each_with_index.map { |benchmark, index| validate_case!(benchmark, index) }
        invalid!("case ids must be unique") unless ids.uniq.length == ids.length
      end

      def validate_case!(benchmark, index)
        path = "cases[#{index}]"
        require_hash!(benchmark, path)
        require_exact_keys!(
          benchmark,
          %w[id label contract parity_checks shared_fixture implementations],
          path
        )
        id = benchmark.fetch("id")
        invalid!("#{path}.id is invalid") unless id.is_a?(String) && id.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
        require_text!(benchmark.fetch("label"), "#{path}.label")
        require_string_array!(benchmark.fetch("contract"), "#{path}.contract")
        validate_parity_checks!(benchmark.fetch("parity_checks"), "#{path}.parity_checks")
        require_json_container!(benchmark.fetch("shared_fixture"), "#{path}.shared_fixture")
        validate_implementations!(benchmark.fetch("implementations"), "#{path}.implementations")
        id
      end

      def validate_parity_checks!(checks, path)
        invalid!("#{path} must be a non-empty array") unless checks.is_a?(Array) && checks.any?

        ids = checks.each_with_index.map do |check, index|
          check_path = "#{path}[#{index}]"
          require_hash!(check, check_path)
          require_exact_keys!(check, %w[id assertion], check_path)
          id = check.fetch("id")
          invalid!("#{check_path}.id is invalid") unless id.is_a?(String) && id.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
          require_text!(check.fetch("assertion"), "#{check_path}.assertion")
          id
        end
        invalid!("#{path} ids must be unique") unless ids.uniq.length == ids.length
      end

      def validate_implementations!(implementations, path)
        require_hash!(implementations, path)
        require_exact_keys!(implementations, IMPLEMENTATIONS, path)
        IMPLEMENTATIONS.each do |implementation|
          validate_implementation!(implementations.fetch(implementation), "#{path}.#{implementation}")
        end
        validate_react_closure!(implementations.fetch("react_rails"), "#{path}.react_rails")
        validate_swift_closure!(implementations.fetch("swift_ui_rails"), "#{path}.swift_ui_rails")
      end

      def validate_react_closure!(implementation, path)
        view_files = implementation.fetch("view_source")
        support_files = implementation.fetch("production_support")
        component = exactly_one_file!(view_files, ->(file) { file.fetch("path").end_with?(".jsx") }, "#{path}.view_source JSX component")
        entry = exactly_one_file!(support_files, ->(file) { file.fetch("path").end_with?("_entry.jsx") }, "#{path} React entry")
        stylesheet = exactly_one_file!(support_files, ->(file) { file.fetch("path").end_with?(".css") }, "#{path} stylesheet")
        rails_view = exactly_one_file!(support_files, ->(file) { file.fetch("path").end_with?(".html.erb") }, "#{path} Rails view")
        package = exactly_one_file!(support_files, ->(file) { file.fetch("path") == "package.json" }, "#{path} package.json")
        gemfile = exactly_one_file!(support_files, ->(file) { file.fetch("path") == "Gemfile.react_rails" }, "#{path} Gemfile")

        manifest = JSON.parse(package.fetch("content"), create_additions: false, max_nesting: 8)
        invalid!("#{path} package.json must be private") unless manifest["private"] == true
        dependencies = manifest.fetch("dependencies", {})
        development_dependencies = manifest.fetch("devDependencies", {})
        invalid!("#{path} must pin react and react-dom") unless %w[react react-dom].all? do |name|
          dependencies[name].is_a?(String) && dependencies[name].match?(/\A\d+\.\d+\.\d+\z/)
        end
        invalid!("#{path} must pin esbuild") unless development_dependencies["esbuild"].is_a?(String) &&
          development_dependencies["esbuild"].match?(/\A\d+\.\d+\.\d+\z/)

        build = manifest.dig("scripts", "build")
        invalid!("#{path} package.json must define a build script") unless build.is_a?(String)
        build_tokens = Shellwords.split(build)
        invalid!("#{path} build must bundle the declared React entry") unless build_tokens.include?(entry.fetch("path"))
        invalid!("#{path} build must use the automatic JSX transform") unless build_tokens.include?("--jsx=automatic")
        invalid!("#{path} build must bundle source") unless build_tokens.include?("--bundle")
        output = build_tokens.find { |token| token.start_with?("--outfile=app/assets/builds/") }
        invalid!("#{path} build must emit under app/assets/builds") unless output&.end_with?(".js")

        output_name = File.basename(output.delete_prefix("--outfile="), ".js")
        stylesheet_name = File.basename(stylesheet.fetch("path"), ".css")
        invalid!("#{path} Rails view must load the built JavaScript") unless rails_view.fetch("content").include?(%("#{output_name}"))
        invalid!("#{path} Rails view must load the feature stylesheet") unless rails_view.fetch("content").include?(%("#{stylesheet_name}"))
        invalid!("#{path} entry must mount with createRoot") unless entry.fetch("content").include?("createRoot")
        invalid!("#{path} entry must import its component") unless entry.fetch("content").include?(File.basename(component.fetch("path"), ".jsx"))
        invalid!("#{path} Gemfile must declare jsbundling-rails") unless gemfile.fetch("content").include?(%(gem "jsbundling-rails"))
      rescue JSON::ParserError, KeyError => error
        invalid!("#{path} React closure is invalid: #{error.message}")
      end

      def validate_swift_closure!(implementation, path)
        view_files = implementation.fetch("view_source")
        support_files = implementation.fetch("production_support")
        component = exactly_one_file!(
          view_files,
          ->(file) { file.fetch("path").match?(%r{\Aapp/components/token_benchmarks/.+_component\.rb\z}) },
          "#{path} component"
        )
        rails_view = exactly_one_file!(support_files, ->(file) { file.fetch("path").end_with?(".html.erb") }, "#{path} Rails view")
        gemfile = exactly_one_file!(support_files, ->(file) { file.fetch("path") == "Gemfile.swift_ui_rails" }, "#{path} Gemfile")

        source_path = Rails.root.join(component.fetch("path"))
        invalid!("#{path} component source is missing") unless source_path.file?
        invalid!("#{path} counted component must byte-match the executable source") unless File.binread(source_path) == component.fetch("content")
        class_name = File.basename(component.fetch("path"), ".rb").camelize
        invalid!("#{path} component must use ApplicationComponent") unless component.fetch("content").include?("class #{class_name} < ApplicationComponent")
        invalid!("#{path} component must declare swift_ui") unless component.fetch("content").include?("swift_ui do")
        invalid!("#{path} Rails view must render the component") unless rails_view.fetch("content").include?("TokenBenchmarks::#{class_name}")
        invalid!("#{path} Gemfile must declare swift_ui_rails") unless gemfile.fetch("content").include?(%(gem "swift_ui_rails"))
      end

      def exactly_one_file!(files, predicate, label)
        matches = files.select(&predicate)
        invalid!("#{label} must contain exactly one file") unless matches.one?

        matches.first
      end

      def validate_implementation!(implementation, path)
        require_hash!(implementation, path)
        require_exact_keys!(implementation, SCOPES, path)

        paths = SCOPES.flat_map do |scope|
          validate_files!(
            implementation.fetch(scope),
            "#{path}.#{scope}",
            required: scope == "view_source"
          )
        end
        invalid!("#{path} file paths must be unique across scopes") unless paths.uniq.length == paths.length
      end

      def validate_files!(files, path, required:)
        invalid!("#{path} must be an array") unless files.is_a?(Array)
        invalid!("#{path} must not be empty") if required && files.empty?
        invalid!("#{path} exceeds #{MAX_FILES_PER_SCOPE} files") if files.length > MAX_FILES_PER_SCOPE

        files.each_with_index.map do |file, index|
          file_path = "#{path}[#{index}]"
          require_hash!(file, file_path)
          require_exact_keys!(file, %w[path content], file_path)
          validate_relative_path!(file.fetch("path"), "#{file_path}.path")
          validate_source!(file.fetch("content"), "#{file_path}.content")
          file.fetch("path")
        end
      end

      def validate_relative_path!(value, path)
        invalid!("#{path} must be a relative source path") unless value.is_a?(String) &&
          value.match?(/\A[a-zA-Z0-9_.\/-]{1,160}\z/) &&
          !value.start_with?("/") &&
          value.split("/").exclude?("..")
      end

      def validate_source!(source, path)
        require_text!(source, path)
        invalid!("#{path} exceeds #{MAX_FILE_BYTES} bytes") if source.bytesize > MAX_FILE_BYTES
        invalid!("#{path} must use LF line endings") if source.include?("\r")
        invalid!("#{path} must end with exactly one newline") unless source.end_with?("\n") && !source.end_with?("\n\n")
        invalid!("#{path} contains trailing whitespace") if source.lines.any? { |line| line.match?(/[ \t]+\n\z/) }
      end

      def require_exact_keys!(hash, keys, path)
        actual = hash.keys.sort
        expected = keys.sort
        invalid!("#{path} keys must be exactly #{expected.join(', ')}") unless actual == expected
      end

      def require_hash!(value, path)
        invalid!("#{path} must be an object") unless value.is_a?(Hash)
      end

      def require_text!(value, path)
        invalid!("#{path} must be non-empty text") unless value.is_a?(String) && value.strip.present?
      end

      def require_string_array!(value, path)
        invalid!("#{path} must be a non-empty string array") unless value.is_a?(Array) &&
          value.any? && value.all? { |entry| entry.is_a?(String) && entry.strip.present? }
      end

      def require_json_container!(value, path)
        invalid!("#{path} must be a non-empty data object or array") unless (value.is_a?(Hash) || value.is_a?(Array)) && value.any?
      end

      def require_version!(value, path)
        invalid!("#{path} must be semantic version text") unless value.is_a?(String) && value.match?(/\A\d+\.\d+\.\d+\z/)
      end

      def invalid!(message)
        raise Invalid, message
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| deep_freeze(key); deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end
    end
  end
end
