# frozen_string_literal: true

require "application_system_test_case"

class StatelessComponentsTest < ApplicationSystemTestCase
  test "filters update URL and content" do
    visit stateless_demo_path
    
    # The first page shows the first three products.
    assert_text "iPhone 15 Pro"
    assert_text "MacBook Air M2"
    assert_text "AirPods Pro"
    
    # Filter by category
    select "Electronics", from: "filter_category"
    click_button "Apply Filters"
    
    # Only electronics should show
    assert_text "iPhone 15 Pro"
    assert_text "MacBook Air M2"
    assert_no_text "Nike Air Max"
    assert_no_text "Levi's 501"
    assert_equal "electronics", current_query_parameters.dig("filters", "category")
  end
  
  test "pagination works through URL params" do
    visit stateless_demo_path
    
    # First page shows first 3 products
    products_on_page = all(".bg-white.p-6.rounded-lg.shadow-sm").count
    assert_equal 3, products_on_page
    
    # Click next page
    click_link "Next →"
    
    # URL should update
    assert_current_path(/page=2/)
    
    # Different products should show
    products_on_page = all(".bg-white.p-6.rounded-lg.shadow-sm").count
    assert products_on_page > 0
  end
  
  test "search works without JavaScript" do
    visit stateless_demo_path
    
    # Search for "nike"
    fill_in "q", with: "nike"
    click_button "Search"
    
    # URL should include search query
    assert_current_path(/q=nike/)
    
    # Search results should show
    within "#search_results" do
      assert_text "Nike Air Max"
      assert_text "Nike Hoodie"
      assert_no_text "iPhone"
    end
  end
  
  test "tabs navigate through URL" do
    visit stateless_demo_path
    
    # Default tab is products
    assert_text "Filter Products"
    
    # Click About tab
    click_link "About"
    
    # URL should update
    assert_current_path(/tab=about/)
    
    # About content should show
    assert_text "About Rails-First Components"
    assert_no_text "Filter Products"
    
    # Click Help tab
    click_link "Help"
    
    # URL should update
    assert_current_path(/tab=help/)
    
    # Help content should show
    assert_text "How It Works"
  end
  
  test "modal controlled by URL params" do
    visit stateless_demo_path(tab: "about")
    
    # No modal initially
    assert_no_selector "dialog#modal[open]"
    
    # Click to open modal
    click_link "Open Info Modal"
    
    # URL should include modal param
    assert_current_path(/modal=info/)
    
    # Modal should be visible
    assert_selector "dialog#modal[open]"
    assert_text "Stateless Modal Example"
    
    # Click close button
    within '[role="dialog"]' do
      find("a.swift-ui-dialog-close").click
    end
    
    # Modal param should be removed
    refute_current_path(/modal=/)
    
    # Modal should be gone
    assert_no_selector "dialog#modal[open]"
  end
  
  test "combined filters and pagination maintain state" do
    visit stateless_demo_path
    
    # Apply filter
    select "Shoes", from: "filter_category"
    click_button "Apply Filters"
    
    # Should show filtered results
    assert_text "Nike Air Max"
    assert_text "Adidas Ultraboost"
    assert_no_text "iPhone"
    
    # Navigate to next page (if available)
    if page.has_link?("Next →")
      click_link "Next →"
      
      # URL should have both filter and page params
      assert_current_path(/page=2/)
      assert_equal "shoes", current_query_parameters.dig("filters", "category")
    end
  end
  
  test "search submits through the native Rails form" do
    visit stateless_demo_path

    fill_in "q", with: "app"
    click_button "Search"

    assert_current_path(/q=app/)
    within "#search_results" do
      assert_text "Apple"
    end
  end

  private

  def current_query_parameters
    Rack::Utils.parse_nested_query(URI.parse(page.current_url).query.to_s)
  end
end
