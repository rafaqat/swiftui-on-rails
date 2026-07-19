# frozen_string_literal: true

class PaginationComponent < SwiftUIRails::Component::Base
  include SwiftUIRails::Security::ComponentValidator
  
  # Constants for better maintainability
  MAX_VISIBLE_PAGES = 7
  
  prop :current_page, type: Integer, required: true
  prop :total_pages, type: Integer, required: true
  prop :base_url, type: String, required: true
  prop :turbo_frame, type: String, default: nil
  
  # Add numeric validation
  validates_number :current_page, min: 1
  validates_number :total_pages, min: 1
  
  def before_render
    super
    # Additional runtime validation
    if current_page > total_pages
      raise ArgumentError, "current_page (#{current_page}) cannot exceed total_pages (#{total_pages})"
    end
    
    # Validate base_url
    begin
      uri = URI.parse(base_url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS) || uri.path.present?
        raise ArgumentError, "base_url must be a valid HTTP(S) URL or path"
      end
    rescue URI::InvalidURIError => e
      raise ArgumentError, "Invalid base_url: #{e.message}"
    end
  end
  
  swift_ui do
    nav(aria: { label: "Pagination" }) do
      hstack(spacing: 2) do
        # Previous button
        if current_page > 1
          pagination_button_style(
            link("← Previous", 
                 destination: url_with_page(current_page - 1),
                 data: turbo_navigation_data)
          )
        else
          pagination_button_style(
            span("← Previous")
          )
            .opacity(50)
            .cursor_not_allowed
        end
        
        # Page numbers (show 5 pages max)
        page_range.each do |page|
          if page == "..."
            span("...")
              .padding_x(3)
              .text_color("gray-500")
          elsif page == current_page
            span(page.to_s)
              .padding_x(3)
              .padding_y(2)
              .background("blue-500")
              .text_color("white")
              .corner_radius("md")
              .font_weight("medium")
          else
            link(page.to_s, 
                 destination: url_with_page(page),
                 data: turbo_navigation_data)
              .padding_x(3)
              .padding_y(2)
              .hover_bg("gray-100")
              .corner_radius("md")
          end
        end
        
        # Next button
        if current_page < total_pages
          pagination_button_style(
            link("Next →", 
                 destination: url_with_page(current_page + 1),
                 data: turbo_navigation_data)
          )
        else
          pagination_button_style(
            span("Next →")
          )
            .opacity(50)
            .cursor_not_allowed
        end
      end
    end
  end
  
  private
  
  def pagination_button_style(element)
    element
      .button_style(:secondary)
      .button_size(:sm)
  end

  def turbo_navigation_data
    turbo_frame ? { turbo_frame: turbo_frame, turbo_action: "advance" } : {}
  end
  
  def url_with_page(page)
    # Use Rails helpers if available in view context
    if respond_to?(:url_for)
      url_for(request.params.merge(page: page, only_path: false))
    else
      # Fallback to manual construction
      uri = URI.parse(base_url)
      params = Rack::Utils.parse_query(uri.query)
      params["page"] = page.to_s
      uri.query = params.to_query
      uri.to_s
    end
  end
  
  def page_range
    return (1..total_pages).to_a if total_pages <= MAX_VISIBLE_PAGES
    
    if current_page <= 3
      [1, 2, 3, 4, "...", total_pages]
    elsif current_page >= total_pages - 2
      [1, "...", total_pages - 3, total_pages - 2, total_pages - 1, total_pages]
    else
      [1, "...", current_page - 1, current_page, current_page + 1, "...", total_pages]
    end
  end
end
