# frozen_string_literal: true

require "application_system_test_case"

class ShowcaseCommerceTest < ApplicationSystemTestCase
  test "customer filters, inspects, buys and checks out without a page reload" do
    visit showcase_commerce_path

    assert_text "Northstar Supply"
    assert_selector "article.commerce-product-card", count: 12

    select "Audio", from: "Category"
    click_button "Apply filters"
    assert_current_path(/category=audio/, wait: 5)
    assert_selector "article.commerce-product-card", count: 3
    assert_text "Aurora Studio Headphones"
    assert_no_text "Orbit Mechanical Keyboard"

    within "#product-aurora-headphones" do
      click_link "Details"
    end
    within "#commerce_quick_view" do
      assert_text "40-hour battery"
      select "2", from: "Quantity"
      click_button "Add to bag"
    end

    assert_no_selector "#commerce_quick_view .commerce-quick-view"
    within "#commerce_cart" do
      assert_text "Aurora Studio Headphones"
      assert_text "£698.00"
    end

    within "#commerce_checkout" do
      fill_in "Full name", with: "Ada Lovelace"
      fill_in "Email", with: "ada@example.test"
      fill_in "Delivery address", with: "12 Analytical Engine Way, London"
      click_button "Place demo order"
      assert_text "Thank you."
      assert_text(/SRV-[A-F0-9]{6}/)
    end

    within "#commerce_cart" do
      assert_text "Your bag is ready"
    end
    assert_no_console_errors
  end

  test "checkout validation is rendered inline and keeps the cart" do
    visit showcase_commerce_path

    within "#product-compass-charger" do
      click_button "+"
    end

    within "#commerce_checkout" do
      fill_in "Full name", with: "A"
      # HTML accepts a local-domain address, while the server-side demo policy
      # requires a dotted domain. This exercises the Turbo validation response.
      fill_in "Email", with: "ada@invalid"
      fill_in "Delivery address", with: "short"
      click_button "Place demo order"

      assert_text "Please check the following"
      assert_text "Enter a valid email address"
    end

    within "#commerce_cart" do
      assert_text "Compass Travel Charger"
    end
  end
end
