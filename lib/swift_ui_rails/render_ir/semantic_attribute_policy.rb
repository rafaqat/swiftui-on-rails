# frozen_string_literal: true

require 'json'
require 'uri'
require_relative 'semantic_action_events'

module SwiftUIRails
  module RenderIR
    # Enforces the framework-neutral browser protocol at the RenderIR boundary.
    # Application-specific controller/method strings are executable vocabulary
    # in disguise, so they are rejected even when nested in ActionView's data:
    # hash form. Only finite data-sui descriptors may reach the shared runtime.
    class SemanticAttributePolicy # rubocop:disable Metrics/ClassLength
      ACTION_ID_PATTERN = /\Aa_[0-9a-f]{32}\z/
      APPLICATION_CALLBACK_PATTERN = /(?:\A|\s)[^\s]+->[a-zA-Z][a-zA-Z0-9_-]*#[a-zA-Z][a-zA-Z0-9_]*(?:\s|\z)/
      BINDING_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]{0,127}\z/
      OBSERVED_STORE_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/
      CLIENT_ID_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/
      COMPONENT_PATTERN = /\A(?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*\z/
      DOM_ID_PATTERN = /\A[A-Za-z][A-Za-z0-9_-]{0,127}\z/
      FOCUS_NAME_PATTERN = /\A[a-z][a-z0-9_]{0,63}\z/
      STORY_CONTEXT_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
      BINDING_TYPES = %w[boolean float integer string].freeze
      CONTENT_TRANSITIONS = %w[identity interpolate numeric-text opacity].freeze
      DOCUMENT_SOURCES = %w[duplicate generated import new template].freeze
      TOOLBAR_PLACEMENTS = %w[
        automatic cancellation_action confirmation_action destructive_action navigation
        primary_action principal secondary_action status
      ].freeze

      JSON_OBJECT_ATTRIBUTES = {
        'data-sui-async-image' => %w[cache],
        'data-sui-canvas' => %w[commands height width],
        'data-sui-dialog' => %w[dismissible kind presented],
        'data-sui-drag' => %w[axis distance keyboardStep],
        'data-sui-focus' => %w[active key value],
        'data-sui-keypress' => %w[keys modifiers phase preventDefault scope],
        'data-sui-long-press' => %w[distance duration],
        'data-sui-tab' => %w[local value],
        'data-sui-tab-panel' => %w[selected value],
        'data-sui-tabs' => %w[initialSelection selection],
        'data-sui-task' => %w[method response trigger url],
        'data-sui-toolbar' => %w[minimizeOnScroll minimizeThreshold orientation overflow],
        'data-sui-workflow' => %w[directUpload drag edge kind label layout maxBytes maxFiles source threshold]
      }.freeze

      ENUM_ATTRIBUTES = {
        'data-sui-async-image-role' => %w[failure image loading],
        'data-sui-binding-type' => BINDING_TYPES,
        'data-sui-canvas-role' => %w[surface],
        'data-sui-content-transition' => CONTENT_TRANSITIONS,
        'data-sui-focus-state' => %w[focused unfocused],
        'data-sui-tap' => %w[1 2],
        'data-sui-toolbar-placement' => TOOLBAR_PLACEMENTS,
        'data-sui-toolbar-priority' => %w[automatic high low pinned],
        'data-sui-toolbar-role' => %w[items overflow overflow-items],
        'data-sui-toolbar-visibility' => %w[automatic overflow visible],
        'data-sui-workflow-role' => %w[
          drag-form drag-item-key drag-placement drag-target-key file-input reorder-item
          swipe-buttons swipe-content swipe-status upload-progress upload-status upload-submit
        ]
      }.freeze

      MARKER_ATTRIBUTES = %w[
        data-sui-keyboard-activate data-sui-lifecycle data-sui-popover data-sui-root
      ].freeze

      ALLOWED_ATTRIBUTES = (%w[
        data-sui-actions
        data-sui-animation-value
        data-sui-binding
        data-sui-component
        data-sui-focus-scope
        data-sui-id
        data-sui-lifecycle-id
        data-sui-observed-stores
        data-sui-present
        data-sui-snapshot
        data-sui-story
        data-sui-story-session
        data-sui-story-variant
        data-sui-stream
        data-sui-update-url
        data-sui-workflow-key
      ] + ENUM_ATTRIBUTES.keys + MARKER_ATTRIBUTES + JSON_OBJECT_ATTRIBUTES.keys).freeze

      def validate!(name, value, path)
        normalized_name = name.downcase
        if normalized_name == 'data'
          validate_data_hash!(value, path)
          return
        end

        reject_application_metadata!(normalized_name, value, path)
        return unless normalized_name.start_with?('data-sui-')

        unless ALLOWED_ATTRIBUTES.include?(normalized_name)
          semantic_error(
            "RenderIR semantic attribute `#{normalized_name}` is not in the finite browser vocabulary.",
            path
          )
        end

        validate_semantic_value!(normalized_name, value, path)
      end

      private

      def validate_data_hash!(value, path)
        return unless value.is_a?(Hash)

        value.each do |key, child|
          data_name = "data-#{key.to_s.dasherize.downcase}"
          validate!(data_name, child, "#{path}.#{key}")
        end
      end

      def reject_application_metadata!(name, value, path)
        application_name = %w[data-action data-controller data-values].include?(name) ||
          (!name.start_with?('data-sui-') && name.match?(/-(?:param|target|value)\z/))
        return unless application_name || value.to_s.match?(APPLICATION_CALLBACK_PATTERN)

        semantic_error(
          'Application JavaScript metadata is unsupported; use a Ruby action or finite data-sui behavior.',
          path
        )
      end

      def validate_semantic_value!(name, value, path)
        unless value.is_a?(String) && value.bytesize <= 256.kilobytes
          semantic_error('RenderIR semantic attribute must be a bounded string.', path)
        end

        if ENUM_ATTRIBUTES.key?(name)
          validate_enum!(value, ENUM_ATTRIBUTES.fetch(name), name.delete_prefix('data-sui-').tr('-', ' '), path)
          return
        end
        if MARKER_ATTRIBUTES.include?(name)
          validate_enum!(value, ['1'], 'boolean marker', path)
          return
        end

        case name
        when 'data-sui-actions' then validate_actions!(value, path)
        when 'data-sui-animation-value' then validate_byte_limit!(value, 512, 'animation value', path)
        when 'data-sui-binding' then validate_pattern!(value, BINDING_PATTERN, 'binding name', path)
        when 'data-sui-component' then validate_pattern!(value, COMPONENT_PATTERN, 'component class', path)
        when 'data-sui-focus-scope' then validate_pattern!(value, FOCUS_NAME_PATTERN, 'focus scope', path)
        when 'data-sui-id' then validate_pattern!(value, DOM_ID_PATTERN, 'component id', path)
        when 'data-sui-lifecycle-id' then validate_pattern!(value, CLIENT_ID_PATTERN, 'lifecycle id', path)
        when 'data-sui-observed-stores' then validate_json_array!(value, path)
        when 'data-sui-present' then validate_pattern!(value, DOM_ID_PATTERN, 'presentation target', path)
        when 'data-sui-snapshot', 'data-sui-stream'
          validate_byte_limit!(value, 128.kilobytes, 'authorization token', path, allow_empty: false)
        when 'data-sui-story', 'data-sui-story-session', 'data-sui-story-variant'
          unless value.match?(STORY_CONTEXT_PATTERN)
            semantic_error('RenderIR invalid story context.', path)
          end
        when 'data-sui-update-url' then validate_update_url!(value, path)
        when 'data-sui-workflow-key'
          validate_printable_string!(value, maximum: 256, label: 'workflow key', path: path)
        else
          validate_json_object!(name, value, path) if JSON_OBJECT_ATTRIBUTES.key?(name)
        end
      end

      def validate_actions!(value, path)
        actions = parse_json!(value, path)
        unless actions.is_a?(Hash) && actions.length.between?(1, 32)
          semantic_error('RenderIR data-sui-actions must be a non-empty bounded object.', path)
        end

        actions.each do |event, action_id|
          valid = event.is_a?(String) && SemanticActionEvents.include?(event) &&
            action_id.is_a?(String) && action_id.match?(ACTION_ID_PATTERN)
          semantic_error('RenderIR data-sui-actions contains an invalid event or action id.', path) unless valid
        end
        return if actions.values.uniq.length == actions.length

        semantic_error('RenderIR data-sui-actions must use a distinct capability for each event.', path)
      end

      def validate_json_object!(name, value, path)
        descriptor = parse_json!(value, path)
        semantic_error("RenderIR #{name} must be a JSON object.", path) unless descriptor.is_a?(Hash)

        unknown = descriptor.keys - JSON_OBJECT_ATTRIBUTES.fetch(name)
        semantic_error("RenderIR #{name} contains unknown key `#{unknown.first}`.", path) if unknown.any?

        case name
        when 'data-sui-async-image' then validate_async_image!(descriptor, path)
        when 'data-sui-canvas' then validate_canvas!(descriptor, path)
        when 'data-sui-dialog' then validate_dialog!(descriptor, path)
        when 'data-sui-drag' then validate_drag!(descriptor, path)
        when 'data-sui-focus' then validate_focus!(descriptor, path)
        when 'data-sui-keypress' then validate_keypress!(descriptor, path)
        when 'data-sui-long-press' then validate_long_press!(descriptor, path)
        when 'data-sui-tab' then validate_tab!(descriptor, path)
        when 'data-sui-tab-panel' then validate_tab_panel!(descriptor, path)
        when 'data-sui-tabs' then validate_tabs!(descriptor, path)
        when 'data-sui-task' then validate_task!(descriptor, path)
        when 'data-sui-toolbar' then validate_toolbar!(descriptor, path)
        when 'data-sui-workflow' then validate_workflow!(descriptor, path)
        end
      end

      def validate_async_image!(descriptor, path)
        require_exact_keys!(descriptor, %w[cache], 'async image', path)
        validate_enum!(descriptor['cache'], ['browser'], 'async image cache', path)
      end

      def validate_canvas!(descriptor, path) # rubocop:disable Metrics/AbcSize
        require_exact_keys!(descriptor, %w[commands height width], 'canvas', path)
        width = descriptor['width']
        height = descriptor['height']
        unless integer_between?(width, 1, 4096) && integer_between?(height, 1, 4096)
          semantic_error('RenderIR canvas dimensions must be integers between 1 and 4096.', path)
        end

        commands = descriptor['commands']
        unless commands.is_a?(Array) && commands.length <= 500
          semantic_error('RenderIR canvas commands must be a bounded array.', path)
        end
        commands.each_with_index do |command, index|
          validate_canvas_command!(command, width: width, height: height, path: "#{path}.commands[#{index}]")
        end
      end

      def validate_canvas_command!(command, width:, height:, path:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        semantic_error('RenderIR canvas command must be an object.', path) unless command.is_a?(Hash)

        schemas = {
          'clear' => %w[color type],
          'fill_rect' => %w[color height type width x y],
          'stroke_rect' => %w[color height line_width type width x y],
          'line' => %w[color line_width type x1 x2 y1 y2],
          'circle' => %w[color fill line_width radius type x y],
          'text' => %w[align color size text type x y]
        }
        type = command['type']
        keys = schemas[type]
        semantic_error("RenderIR canvas command type `#{type}` is unsupported.", path) unless keys
        require_exact_keys!(command, keys, 'canvas command', path)

        validate_canvas_color!(command['color'], path)
        coordinate_keys = case type
                          when 'line' then { 'x1' => width, 'x2' => width, 'y1' => height, 'y2' => height }
                          when 'fill_rect', 'stroke_rect', 'circle', 'text' then { 'x' => width, 'y' => height }
                          else {}
                          end
        coordinate_keys.each do |key, maximum|
          next if number_between?(command[key], 0, maximum)

          semantic_error("RenderIR canvas coordinate `#{key}` is outside its surface.", path)
        end

        case type
        when 'fill_rect', 'stroke_rect'
          validate_positive_number!(command['width'], maximum: width, label: 'rectangle width', path: path)
          validate_positive_number!(command['height'], maximum: height, label: 'rectangle height', path: path)
        when 'circle'
          validate_positive_number!(command['radius'], maximum: [width, height].max, label: 'circle radius', path: path)
          validate_boolean!(command['fill'], 'circle fill', path)
        when 'text'
          validate_printable_string!(command['text'], maximum: 200, label: 'canvas text', path: path)
          validate_enum!(command['align'], %w[center end start], 'canvas text alignment', path)
          unless integer_between?(command['size'], 8, 96)
            semantic_error('RenderIR canvas text size must be between 8 and 96.', path)
          end
        end
        if %w[stroke_rect line circle].include?(type)
          validate_positive_number!(command['line_width'], maximum: 64, label: 'line width', path: path)
        end
      end

      def validate_canvas_color!(value, path)
        return if value.is_a?(String) && (value == 'transparent' || value.match?(/\A#[0-9a-f]{6}\z/i))

        semantic_error('RenderIR canvas color must be transparent or six-digit hex.', path)
      end

      def validate_dialog!(descriptor, path)
        require_exact_keys!(descriptor, %w[dismissible kind presented], 'dialog', path)
        validate_enum!(descriptor['kind'], %w[alert confirmation sheet], 'dialog kind', path)
        validate_boolean!(descriptor['presented'], 'dialog presented', path)
        validate_boolean!(descriptor['dismissible'], 'dialog dismissible', path)
      end

      def validate_drag!(descriptor, path)
        require_keys!(descriptor, %w[axis distance], 'drag', path)
        validate_enum!(descriptor['axis'], %w[both horizontal vertical], 'drag axis', path)
        unless number_between?(descriptor['distance'], 0, 200)
          semantic_error('RenderIR drag distance must be between 0 and 200.', path)
        end
        return unless descriptor.key?('keyboardStep')

        validate_positive_number!(descriptor['keyboardStep'], maximum: 10_000, label: 'drag keyboard step', path: path)
      end

      def validate_focus!(descriptor, path)
        require_exact_keys!(descriptor, %w[active key value], 'focus', path)
        unless descriptor['key'].is_a?(String) && descriptor['key'].match?(FOCUS_NAME_PATTERN)
          semantic_error('RenderIR focus key is invalid.', path)
        end
        validate_scalar_string!(descriptor['value'], maximum: 128, label: 'focus value', path: path)
        validate_boolean!(descriptor['active'], 'focus active', path)
      end

      def validate_keypress!(descriptor, path)
        require_exact_keys!(descriptor, %w[keys modifiers phase preventDefault scope], 'keypress', path)
        keys = descriptor['keys']
        unless keys.is_a?(Array) && keys.length.between?(1, 32) &&
            keys.all? { |key| valid_scalar_string?(key, maximum: 64) }
          semantic_error('RenderIR keypress keys must be a non-empty bounded string array.', path)
        end
        modifiers = descriptor['modifiers']
        unless modifiers.is_a?(Array) && modifiers.length <= 4 && modifiers.uniq == modifiers &&
            (modifiers - %w[alt control meta shift]).empty?
          semantic_error('RenderIR keypress modifiers are invalid.', path)
        end
        validate_enum!(descriptor['phase'], %w[keydown keyup], 'keypress phase', path)
        validate_enum!(descriptor['scope'], %w[element window], 'keypress scope', path)
        validate_boolean!(descriptor['preventDefault'], 'keypress preventDefault', path)
      end

      def validate_long_press!(descriptor, path)
        require_exact_keys!(descriptor, %w[distance duration], 'long press', path)
        unless number_between?(descriptor['duration'], 200, 10_000) && number_between?(descriptor['distance'], 0, 200)
          semantic_error('RenderIR long press duration or distance is outside its finite range.', path)
        end
      end

      def validate_tab!(descriptor, path)
        require_exact_keys!(descriptor, %w[local value], 'tab', path)
        validate_pattern_value!(descriptor['value'], DOM_ID_PATTERN, 'tab value', path)
        validate_boolean!(descriptor['local'], 'tab local', path)
      end

      def validate_tab_panel!(descriptor, path)
        require_exact_keys!(descriptor, %w[selected value], 'tab panel', path)
        validate_pattern_value!(descriptor['value'], DOM_ID_PATTERN, 'tab panel value', path)
        validate_boolean!(descriptor['selected'], 'tab panel selected', path)
      end

      def validate_tabs!(descriptor, path)
        require_exact_keys!(descriptor, %w[initialSelection selection], 'tabs', path)
        validate_pattern_value!(descriptor['selection'], DOM_ID_PATTERN, 'tab selection', path)
        validate_pattern_value!(descriptor['initialSelection'], DOM_ID_PATTERN, 'initial tab selection', path)
      end

      def validate_task!(descriptor, path)
        require_exact_keys!(descriptor, %w[method response trigger url], 'task', path)
        validate_enum!(descriptor['method'], %w[GET POST], 'task method', path)
        validate_enum!(descriptor['trigger'], %w[appear manual], 'task trigger', path)
        validate_enum!(descriptor['response'], %w[event replace_content], 'task response', path)
        validate_same_origin_path!(descriptor['url'], 'task URL', path)
        if descriptor['method'] == 'POST' && descriptor['trigger'] != 'manual'
          semantic_error('RenderIR POST tasks must use the manual trigger.', path)
        end
      end

      def validate_toolbar!(descriptor, path)
        require_exact_keys!(descriptor, %w[minimizeOnScroll minimizeThreshold orientation overflow], 'toolbar', path)
        validate_enum!(descriptor['orientation'], %w[horizontal vertical], 'toolbar orientation', path)
        validate_boolean!(descriptor['overflow'], 'toolbar overflow', path)
        validate_boolean!(descriptor['minimizeOnScroll'], 'toolbar minimizeOnScroll', path)
        unless integer_between?(descriptor['minimizeThreshold'], 0, 1000)
          semantic_error('RenderIR toolbar minimizeThreshold must be between 0 and 1000.', path)
        end
        if descriptor['minimizeOnScroll'] && !descriptor['overflow']
          semantic_error('RenderIR toolbar scroll minimization requires overflow.', path)
        end
      end

      def validate_workflow!(descriptor, path)
        case descriptor['kind']
        when 'reorder' then validate_reorder_workflow!(descriptor, path)
        when 'swipe' then validate_swipe_workflow!(descriptor, path)
        when 'document' then validate_document_workflow!(descriptor, path)
        else semantic_error("RenderIR workflow kind `#{descriptor['kind']}` is unsupported.", path)
        end
      end

      def validate_reorder_workflow!(descriptor, path)
        require_exact_keys!(descriptor, %w[drag kind layout], 'reorder workflow', path)
        validate_enum!(descriptor['layout'], %w[custom grid list], 'reorder layout', path)
        validate_boolean!(descriptor['drag'], 'reorder drag', path)
      end

      def validate_swipe_workflow!(descriptor, path)
        require_exact_keys!(descriptor, %w[edge kind label threshold], 'swipe workflow', path)
        validate_enum!(descriptor['edge'], %w[leading trailing], 'swipe edge', path)
        unless integer_between?(descriptor['threshold'], 24, 240)
          semantic_error('RenderIR swipe threshold must be between 24 and 240.', path)
        end
        validate_printable_string!(descriptor['label'], maximum: 160, label: 'swipe label', path: path)
      end

      def validate_document_workflow!(descriptor, path)
        require_exact_keys!(
          descriptor,
          %w[directUpload kind maxBytes maxFiles source],
          'document workflow',
          path
        )
        unless integer_between?(descriptor['maxBytes'], 1, 2.gigabytes)
          semantic_error('RenderIR document maxBytes is outside its finite range.', path)
        end
        unless integer_between?(descriptor['maxFiles'], 1, 20)
          semantic_error('RenderIR document maxFiles must be between 1 and 20.', path)
        end
        validate_boolean!(descriptor['directUpload'], 'document directUpload', path)
        validate_enum!(descriptor['source'], DOCUMENT_SOURCES, 'document source', path)
      end

      def validate_json_array!(value, path)
        parsed = parse_json!(value, path)
        valid = parsed.is_a?(Array) && parsed.length <= 64 && parsed.uniq == parsed && parsed.all? do |entry|
          entry.is_a?(String) && entry.match?(OBSERVED_STORE_PATTERN)
        end
        semantic_error('RenderIR observed stores must be a bounded JSON string array.', path) unless valid
      end

      def parse_json!(value, path)
        JSON.parse(value, max_nesting: 32)
      rescue JSON::ParserError
        semantic_error('RenderIR semantic descriptor contains invalid JSON.', path)
      end

      def require_exact_keys!(descriptor, keys, label, path)
        require_keys!(descriptor, keys, label, path)
        extra = descriptor.keys - keys
        semantic_error("RenderIR #{label} contains unknown key `#{extra.first}`.", path) if extra.any?
      end

      def require_keys!(descriptor, keys, label, path)
        missing = keys - descriptor.keys
        semantic_error("RenderIR #{label} is missing key `#{missing.first}`.", path) if missing.any?
      end

      def validate_update_url!(value, path)
        return if value == '/swift_ui/components/update'

        semantic_error('RenderIR semantic update URL must use the fixed component endpoint.', path)
      end

      def validate_same_origin_path!(value, label, path)
        valid = value.is_a?(String) && value.bytesize <= 2048 && value.start_with?('/') &&
          !value.start_with?('//') && !value.include?('\\') && !value.match?(/[\u0000-\u001f\u007f]/)
        if valid
          uri = URI.parse(value)
          valid = uri.relative? && uri.host.nil? && uri.userinfo.nil?
        end
        semantic_error("RenderIR #{label} must be a same-origin absolute path.", path) unless valid
      rescue URI::InvalidURIError
        semantic_error("RenderIR #{label} must be a same-origin absolute path.", path)
      end

      def validate_pattern!(value, pattern, label, path)
        return if value.match?(pattern)

        semantic_error("RenderIR semantic #{label} is invalid.", path)
      end

      def validate_pattern_value!(value, pattern, label, path)
        return if value.is_a?(String) && value.match?(pattern)

        semantic_error("RenderIR semantic #{label} is invalid.", path)
      end

      def validate_enum!(value, allowed, label, path)
        return if allowed.include?(value)

        semantic_error("RenderIR semantic #{label} is invalid.", path)
      end

      def validate_boolean!(value, label, path)
        return if value == true || value == false

        semantic_error("RenderIR #{label} must be boolean.", path)
      end

      def validate_positive_number!(value, maximum:, label:, path:)
        return if number_between?(value, Float::MIN, maximum) && value.positive?

        semantic_error("RenderIR #{label} must be positive and at most #{maximum}.", path)
      end

      def validate_printable_string!(value, maximum:, label:, path:)
        return if valid_scalar_string?(value, maximum: maximum) && !value.empty?

        semantic_error("RenderIR #{label} must contain 1 to #{maximum} non-control bytes.", path)
      end

      def validate_scalar_string!(value, maximum:, label:, path:)
        return if valid_scalar_string?(value, maximum: maximum)

        semantic_error("RenderIR #{label} must contain at most #{maximum} non-control bytes.", path)
      end

      def valid_scalar_string?(value, maximum:)
        value.is_a?(String) && value.valid_encoding? && value.bytesize <= maximum &&
          !value.match?(/[\u0000-\u001f\u007f]/)
      end

      def validate_byte_limit!(value, maximum, label, path, allow_empty: true)
        valid = value.bytesize <= maximum && (allow_empty || !value.empty?)
        semantic_error("RenderIR #{label} exceeds its finite byte limit.", path) unless valid
      end

      def integer_between?(value, minimum, maximum)
        value.is_a?(Integer) && value.between?(minimum, maximum)
      end

      def number_between?(value, minimum, maximum)
        value.is_a?(Numeric) && (!value.is_a?(Float) || value.finite?) && value.between?(minimum, maximum)
      end

      def semantic_error(message, path)
        raise InvalidStructure.new(message, path: path)
      end
    end
  end
end
