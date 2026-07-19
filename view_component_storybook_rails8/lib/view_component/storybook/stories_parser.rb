# frozen_string_literal: true

require "ripper"

module ViewComponent
  module Storybook
    class StoriesParser
      def initialize(paths)
        @paths = paths
        @after_parse_callbacks = []
        @after_parse_once_callbacks = []
        @parsing = false
      end

      def parse(&block)
        return if @parsing

        @parsing = true
        @after_parse_once_callbacks << block if block

        begin
          # Simple file-based parsing instead of YARD
          story_classes = []

          @paths.each do |path|
            Dir.glob(File.join(path, "**/*_stories.rb")).each do |file|
              # Load the file
              require file

              # Extract class name from filename
              class_name = File.basename(file, ".rb").camelize

              # Try to constantize it
              begin
                klass = class_name.constantize
                if klass < ViewComponent::Storybook::Stories
                  story_classes << MockCodeObject.new(class_name, file)
                end
              rescue NameError => e
                Rails.logger.debug "Could not load story class #{class_name}: #{e.message}"
              end
            end
          end

          # Create a mock registry
          registry = MockRegistry.new(story_classes)
          run_callbacks(registry)
        ensure
          @after_parse_once_callbacks = []
          @parsing = false
        end
      end

      def after_parse(&block)
        @after_parse_callbacks << block
      end

      attr_reader :paths

      protected

      def callbacks
        [
          *@after_parse_callbacks,
          *@after_parse_once_callbacks
        ]
      end

      def run_callbacks(registry)
        callbacks.each { |cb| cb.call(registry) }
        @after_parse_once_callbacks = []
      end
      
      # Mock classes to replace YARD functionality
      class MockCodeObject
        attr_reader :path
        
        def initialize(path, file_path = nil)
          # Ensure path is never nil and is a valid string
          if path.nil? || path.to_s.empty?
            Rails.logger.warn "MockCodeObject initialized with nil or empty path. File: #{file_path}"
            @path = file_path ? File.basename(file_path, ".rb").camelize : "UnknownStory"
          else
            @path = path.to_s
          end
          
          @file_path = file_path
          # Try to get the actual class to read its methods
          @story_class = @path.constantize rescue nil
        end
        
        def file
          @file_path || ""
        end
        
        def meths
          return [] unless @story_class
          
          # Get public instance methods and create mock method objects
          methods = @story_class.public_instance_methods(false)
          methods.map { |method_name| MockMethodObject.new(@story_class, method_name) }
        end
      end
      
      class MockMethodObject
        attr_reader :name
        
        def initialize(story_class, name)
          @story_class = story_class
          @name = name
          @method = story_class.instance_method(name)
        end

        # Match the small part of YARD's method-object API used by the controls
        # collection. Ruby reflection exposes parameter kinds and names but not
        # their default values, so defaults are recovered from the method's
        # source tokens.
        def parameters
          @parameters ||= @method.parameters.filter_map do |type, param|
            next unless param

            name = %i[key keyreq].include?(type) ? "#{param}:" : param.to_s
            [name, parameter_defaults[param]]
          end
        end

        def default_value(param)
          expression = parameter_defaults[param.to_sym]
          return unless expression

          file, line = @method.source_location
          @story_class.new.instance_eval(expression, file || "(storybook)", line || 1)
        rescue StandardError => e
          Rails.logger.debug "Could not infer default for #{@story_class}##{name}(#{param}): #{e.message}"
          nil
        end

        private

        def parameter_defaults
          @parameter_defaults ||= parameter_segments.each_with_object({}) do |segment, defaults|
            source = segment.reject { |token| token[1] == :on_comment }.map { |token| token[2] }.join.strip

            if (match = source.match(/\A([a-zA-Z_]\w*):\s*(.+)\z/m))
              defaults[match[1].to_sym] = match[2].strip
            elsif (match = source.match(/\A([a-zA-Z_]\w*)\s*=\s*(.+)\z/m))
              defaults[match[1].to_sym] = match[2].strip
            end
          end
        end

        def parameter_segments
          tokens = method_parameter_tokens
          segments = [[]]
          delimiters = []

          tokens.each do |token|
            type = token[1]

            if type == :on_comma && delimiters.empty?
              segments << []
              next
            end

            segments.last << token
            update_delimiters(delimiters, type)
          end

          segments.reject(&:empty?)
        end

        def method_parameter_tokens
          file, source_line = @method.source_location
          return [] unless file && source_line && File.file?(file)

          tokens = Ripper.lex(File.read(file))
          definition_index = tokens.index do |position, type, text, _state|
            position[0] == source_line && type == :on_kw && text == "def"
          end
          return [] unless definition_index

          name_index = tokens.each_index.find do |index|
            index > definition_index && tokens[index][2] == name.to_s
          end
          return [] unless name_index

          index = next_significant_token(tokens, name_index + 1)
          return [] unless index

          if tokens[index][1] == :on_lparen
            parenthesized_parameter_tokens(tokens, index + 1)
          else
            unparenthesized_parameter_tokens(tokens, index)
          end
        end

        def next_significant_token(tokens, index)
          index += 1 while index < tokens.length && %i[on_sp on_comment on_ignored_nl].include?(tokens[index][1])
          index if index < tokens.length
        end

        def parenthesized_parameter_tokens(tokens, index)
          result = []
          delimiters = [:on_rparen]

          while index < tokens.length
            token = tokens[index]
            type = token[1]
            break if type == :on_rparen && delimiters == [:on_rparen]

            result << token
            update_delimiters(delimiters, type)
            index += 1
          end

          result
        end

        def unparenthesized_parameter_tokens(tokens, index)
          result = []
          delimiters = []

          while index < tokens.length
            token = tokens[index]
            type = token[1]
            break if delimiters.empty? && %i[on_nl on_semicolon].include?(type)

            result << token
            update_delimiters(delimiters, type)
            index += 1
          end

          result
        end

        def update_delimiters(delimiters, type)
          closing_type = {
            on_lparen: :on_rparen,
            on_lbracket: :on_rbracket,
            on_lbrace: :on_rbrace,
            on_tlambeg: :on_rbrace,
            on_embexpr_beg: :on_embexpr_end
          }[type]

          if closing_type
            delimiters << closing_type
          elsif type == delimiters.last
            delimiters.pop
          end
        end
      end
      
      class MockRegistry
        def initialize(classes)
          @classes = classes
        end
        
        def all(type)
          type == :class ? @classes : []
        end
      end
    end
  end
end
