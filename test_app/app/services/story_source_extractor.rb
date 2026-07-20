# frozen_string_literal: true

# Extracts trusted DSL source code for display in the storybook and demo pages.
# Component sources must live inside the host application's component
# directory; story method sources are read only from files provided by the
# trusted story registry, never from request-derived paths.
class StorySourceExtractor
  MAX_SOURCE_BYTES = 256.kilobytes

  class << self
    # Returns [path, source] for a component class defined under
    # app/components, or nil when the class is anonymous, missing, oversized,
    # or defined outside the trusted directory.
    def component_source(component_class)
      return unless component_class&.name

      location = Object.const_source_location(component_class.name)&.first
      return unless location

      component_root = Rails.root.join("app/components").realpath
      source_path = Pathname.new(location).realpath
      return unless source_path.to_s.start_with?("#{component_root}#{File::SEPARATOR}")
      return unless source_path.file?
      return if source_path.size > MAX_SOURCE_BYTES

      [source_path, source_path.read]
    rescue NameError, SystemCallError
      nil
    end

    # Returns the source of a single method definition from a story file, or
    # nil when the file or method cannot be found.
    def method_source(file_path, method_name)
      begin
        lines = File.read(file_path).split("\n")
      rescue Errno::ENOENT => e
        Rails.logger.error "Story file not found: #{file_path} - #{e.message}"
        return nil
      rescue StandardError => e
        Rails.logger.error "Error reading story file: #{file_path} - #{e.message}"
        return nil
      end

      method_start = nil
      indent_level = nil

      lines.each_with_index do |line, index|
        if line.match(/^\s*def\s+#{Regexp.escape(method_name)}(\s|\(|$)/)
          method_start = index
          indent_level = line[/^\s*/].length
          break
        end
      end

      return nil unless method_start

      method_end = nil
      (method_start + 1...lines.length).each do |index|
        line = lines[index]
        next if line.strip.empty?

        if line.match?(/^\s*end(?:\s+#.*)?\s*$/) && line[/^\s*/].length == indent_level
          method_end = index
          break
        end
      end

      return nil unless method_end

      lines[method_start..method_end].join("\n")
    end
  end
end
