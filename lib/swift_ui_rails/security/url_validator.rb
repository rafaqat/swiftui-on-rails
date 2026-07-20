# frozen_string_literal: true

require "set"

module SwiftUIRails
  module Security
    # SECURITY: Validates URLs to prevent loading from untrusted sources
    module URLValidator
      # List of approved external domains for resources
      APPROVED_DOMAINS = [
        # Development/placeholder services
        'picsum.photos',
        'via.placeholder.com',
        'placehold.co',
        'placeholder.com',
        
        # CDN services
        'cdn.jsdelivr.net',
        'unpkg.com',
        'cdnjs.cloudflare.com',
        
        # Common image services
        'images.unsplash.com',
        'i.imgur.com',
        'gravatar.com',
        
        # Add your approved domains here
      ].freeze

      # Embeddable documents have a materially different threat model from
      # images and links. Keep their allowlist deliberately small instead of
      # inheriting APPROVED_DOMAINS (which includes package CDNs and arbitrary
      # image hosts that should never be framed).
      APPROVED_EMBED_DOMAINS = %w[
        www.youtube-nocookie.com
        player.vimeo.com
      ].freeze
      
      # URL schemes that are allowed
      ALLOWED_SCHEMES = %w[http https].freeze
      
      # Dangerous URL patterns
      DANGEROUS_PATTERNS = [
        /javascript:/i,
        /data:(?!image\/(png|jpg|jpeg|gif|webp|svg\+xml))/i,
        /vbscript:/i,
        /file:/i,
        /about:/i,
        /chrome:/i,
        /chrome-extension:/i
      ].freeze

      @additional_approved_domains = Set.new
      @approved_domains_mutex = Mutex.new
      @additional_approved_embed_domains = Set.new
      @approved_embed_domains_mutex = Mutex.new
      
      class << self
        # Validate and sanitize a URL
        def validate_url(url, options = {})
          return options[:fallback] if url.nil? || url.empty?

          # Check for dangerous patterns first
          if contains_dangerous_pattern?(url)
            Rails.logger.warn "Blocked dangerous URL pattern: #{url}"
            return options[:fallback]
          end

          # Parse the URL
          begin
            uri = URI.parse(url)
          rescue URI::InvalidURIError
            Rails.logger.warn "Invalid URL format: #{url}"
            return options[:fallback]
          end
          
          # URI treats network-path references such as //evil.example/image as
          # relative even though the browser will make an external request.
          # Apply the same host allowlist used for absolute URLs.
          if uri.relative?
            if uri.host
              if options[:require_approved_domains] && !approved_domain?(uri.host)
                Rails.logger.warn "Unapproved external domain: #{uri.host}"
                return options[:fallback]
              end

              return url
            end

            return url if options[:allow_relative] != false
            Rails.logger.warn "Relative URLs not allowed: #{url}"
            return options[:fallback]
          end

          # Check scheme
          unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
            Rails.logger.warn "Disallowed URL scheme: #{uri.scheme} in #{url}"
            return options[:fallback]
          end
          
          # Check domain if external URLs need approval
          if options[:require_approved_domains]
            unless approved_domain?(uri.host)
              Rails.logger.warn "Unapproved external domain: #{uri.host}"
              return options[:fallback] || nil
            end
          end
          
          # Return the validated URL
          url
        end
        
        # Check if URL is from an approved domain
        def approved_domain?(host)
          return false if host.nil?
          
          host_lower = host.downcase
          
          approved_domains.any? do |approved|
            # Exact match or subdomain match
            host_lower == approved || host_lower.end_with?(".#{approved}")
          end
        end
        
        # Check if URL contains dangerous patterns
        def contains_dangerous_pattern?(url)
          DANGEROUS_PATTERNS.any? { |pattern| url.match?(pattern) }
        end
        
        # Validate image source URL
        def validate_image_src(src, options = {})
          # Set default options for images
          options = {
            allow_relative: true,
            require_approved_domains: true,
            fallback: '/images/placeholder.png'
          }.merge(options)
          
          validate_url(src, options)
        end
        
        # Validate script source URL.
        #
        # Scripts are an execution trust boundary, so external hosts are never
        # allowed here — public package CDNs (unpkg, jsdelivr, cdnjs) serve
        # arbitrary packages, so an attacker-controlled src could execute code
        # in the page. Only application-relative, host-less paths are accepted;
        # pin external scripts through a dedicated manifest with SRI instead.
        def validate_script_src(src, options = {})
          source = src.to_s
          return options[:fallback] if source.empty?
          return options[:fallback] if contains_dangerous_pattern?(source)

          begin
            uri = URI.parse(source)
          rescue URI::InvalidURIError
            return options[:fallback]
          end

          # Reject any absolute URL, scheme, or network-path reference (//host).
          return options[:fallback] if uri.scheme || uri.host

          source
        end

        # Validate an iframe/WebView source. Relative URLs are same-origin and
        # may be enabled for application-owned embeds. Every external host must
        # be on the dedicated embed allowlist, including protocol-relative URLs.
        def validate_embed_src(src, options = {})
          source = src.to_s
          return nil if source.empty?

          options = { allow_relative: true, fallback: nil }.merge(options)
          safe_url = validate_url(
            source,
            allow_relative: options[:allow_relative],
            require_approved_domains: false,
            fallback: nil
          )
          return options[:fallback] unless safe_url

          uri = URI.parse(safe_url)
          if uri.host
            secure_transport = uri.scheme.nil? || uri.scheme.casecmp?("https")
            return safe_url if secure_transport && approved_embed_domain?(uri.host) && uri.userinfo.nil?

            Rails.logger.warn "Unapproved embed domain: #{uri.host}"
            return options[:fallback]
          end

          # Absolute URLs without a host (and unusual opaque URI forms) are not
          # useful iframe sources. A local source must be a normal relative path.
          return options[:fallback] unless uri.relative? && options[:allow_relative]
          return options[:fallback] if source.start_with?("//") || source.match?(/[\u0000-\u001f\u007f]/)

          safe_url
        rescue URI::InvalidURIError
          options[:fallback]
        end

        def approved_embed_domain?(host)
          return false if host.nil?

          host_lower = host.downcase
          approved_embed_domains.any? do |approved|
            host_lower == approved || host_lower.end_with?(".#{approved}")
          end
        end
        
        # Validate link href
        def validate_link_href(href, options = {})
          # Links can be more permissive
          options = {
            allow_relative: true,
            require_approved_domains: false,
            fallback: '#'
          }.merge(options)
          
          validate_url(href, options)
        end
        
        # Generate a safe placeholder image URL
        def safe_placeholder_image(width: 400, height: 400, text: nil)
          # Use a safe placeholder service
          if text
            "https://via.placeholder.com/#{width}x#{height}?text=#{ERB::Util.url_encode(text)}"
          else
            "https://via.placeholder.com/#{width}x#{height}"
          end
        end
        
        # Add a domain to the approved list at runtime (for configuration)
        def add_approved_domain(domain)
          return false if domain.nil? || domain.empty?

          # Require at least two valid labels so a bare TLD ("com") cannot be
          # approved and then match every "*.com" host via the suffix check.
          unless valid_embed_domain?(domain)
            Rails.logger.warn "Invalid domain format: #{domain}"
            return false
          end

          normalized_domain = domain.downcase
          @approved_domains_mutex.synchronize do
            @additional_approved_domains.add(normalized_domain)
          end
          
          true
        end

        # Applications may extend the embed policy during boot. This API is
        # intentionally separate from add_approved_domain so approving an image
        # host never grants it permission to execute a framed document.
        def add_approved_embed_domain(domain)
          return false if domain.nil? || domain.empty?
          return false unless valid_embed_domain?(domain)

          normalized_domain = domain.downcase
          @approved_embed_domains_mutex.synchronize do
            @additional_approved_embed_domains.add(normalized_domain)
          end

          true
        end
        
        # Configuration helper for Rails apps
        def configure
          yield self if block_given?
        end

        private

        def approved_domains
          additional_domains = @approved_domains_mutex.synchronize do
            @additional_approved_domains.to_a
          end

          APPROVED_DOMAINS + additional_domains
        end


        def approved_embed_domains
          additional_domains = @approved_embed_domains_mutex.synchronize do
            @additional_approved_embed_domains.to_a
          end

          APPROVED_EMBED_DOMAINS + additional_domains
        end

        def valid_embed_domain?(domain)
          return false if domain.length > 253

          labels = domain.split(".")
          labels.length >= 2 && labels.all? do |label|
            label.length.between?(1, 63) && label.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/i)
          end
        end
      end
    end
  end
end
