# frozen_string_literal: true

module Showcase
  class Catalog
    Product = Data.define(
      :id,
      :name,
      :category,
      :category_name,
      :description,
      :price_cents,
      :stock,
      :rating,
      :reviews,
      :badge,
      :symbol,
      :tone,
      :features
    ) do
      def in_stock?
        stock.positive?
      end
    end

    SORTS = {
      "featured" => "Featured",
      "price_asc" => "Price: low to high",
      "price_desc" => "Price: high to low",
      "rating" => "Top rated"
    }.freeze

    PRICE_CAPS = {
      10_000 => "Up to £100",
      20_000 => "Up to £200",
      35_000 => "Up to £350",
      50_000 => "Up to £500",
      75_000 => "Up to £750"
    }.freeze

    PRODUCTS = [
      Product.new(
        id: "aurora-headphones",
        name: "Aurora Studio Headphones",
        category: "audio",
        category_name: "Audio",
        description: "Reference-grade wireless headphones with adaptive spatial audio and a calm, all-day fit.",
        price_cents: 34_900,
        stock: 12,
        rating: 4.9,
        reviews: 184,
        badge: "Editor's pick",
        symbol: "◖◗",
        tone: "violet",
        features: [ "40-hour battery", "Lossless USB-C audio", "Adaptive noise control" ]
      ),
      Product.new(
        id: "pulse-monitors",
        name: "Pulse Mini Monitors",
        category: "audio",
        category_name: "Audio",
        description: "Compact active speakers tuned for near-field listening, editing and small-room mixes.",
        price_cents: 21_900,
        stock: 4,
        rating: 4.7,
        reviews: 96,
        badge: "Low stock",
        symbol: "◉",
        tone: "coral",
        features: [ "Balanced TRS input", "Bluetooth 5.3", "Room EQ switches" ]
      ),
      Product.new(
        id: "field-recorder",
        name: "Field Notes Recorder",
        category: "audio",
        category_name: "Audio",
        description: "A pocketable 32-bit recorder designed for interviews, ambience and live sessions.",
        price_cents: 28_900,
        stock: 0,
        rating: 4.8,
        reviews: 72,
        badge: "Sold out",
        symbol: "▥",
        tone: "slate",
        features: [ "32-bit float", "Stereo condenser pair", "USB microphone mode" ]
      ),
      Product.new(
        id: "orbit-keyboard",
        name: "Orbit Mechanical Keyboard",
        category: "workspace",
        category_name: "Workspace",
        description: "A low-profile aluminium keyboard with quiet tactile switches and three-device pairing.",
        price_cents: 17_900,
        stock: 21,
        rating: 4.8,
        reviews: 231,
        badge: "Bestseller",
        symbol: "⌨",
        tone: "blue",
        features: [ "Hot-swappable switches", "Mac and Windows layers", "Six-week battery" ]
      ),
      Product.new(
        id: "arc-dock",
        name: "Arc Twelve-Port Dock",
        category: "workspace",
        category_name: "Workspace",
        description: "One compact desk hub for displays, storage, networking and 100 W laptop charging.",
        price_cents: 12_900,
        stock: 17,
        rating: 4.6,
        reviews: 148,
        badge: nil,
        symbol: "⌁",
        tone: "mint",
        features: [ "Dual 4K displays", "2.5 Gb Ethernet", "100 W power delivery" ]
      ),
      Product.new(
        id: "canvas-display",
        name: "Canvas 5K Display",
        category: "workspace",
        category_name: "Workspace",
        description: "A colour-calibrated 27-inch display made for precise creative work and clean desks.",
        price_cents: 69_900,
        stock: 6,
        rating: 4.9,
        reviews: 88,
        badge: "New",
        symbol: "▣",
        tone: "amber",
        features: [ "5K Retina panel", "98% DCI-P3", "Single-cable USB-C" ]
      ),
      Product.new(
        id: "lumen-camera",
        name: "Lumen Pocket Camera",
        category: "imaging",
        category_name: "Imaging",
        description: "A small fixed-lens camera with a large sensor and direct, distraction-free controls.",
        price_cents: 54_900,
        stock: 9,
        rating: 4.7,
        reviews: 121,
        badge: "New",
        symbol: "◉",
        tone: "rose",
        features: [ "24 MP APS-C sensor", "35 mm equivalent lens", "Weather-sealed body" ]
      ),
      Product.new(
        id: "prism-lens",
        name: "Prism 50 mm Lens",
        category: "imaging",
        category_name: "Imaging",
        description: "A bright standard prime with gentle rendering, fast focus and close-up versatility.",
        price_cents: 32_900,
        stock: 14,
        rating: 4.8,
        reviews: 64,
        badge: nil,
        symbol: "◎",
        tone: "indigo",
        features: [ "f/1.8 aperture", "Silent linear motor", "0.25 m close focus" ]
      ),
      Product.new(
        id: "rover-pack",
        name: "Rover Camera Pack",
        category: "travel",
        category_name: "Travel",
        description: "A weather-ready day pack with configurable camera storage and a breathable harness.",
        price_cents: 18_900,
        stock: 8,
        rating: 4.6,
        reviews: 109,
        badge: nil,
        symbol: "⌂",
        tone: "forest",
        features: [ "24-litre capacity", "Side camera access", "Recycled sailcloth shell" ]
      ),
      Product.new(
        id: "compass-charger",
        name: "Compass Travel Charger",
        category: "travel",
        category_name: "Travel",
        description: "A palm-sized universal charger for a laptop, phone and watch in more than 150 countries.",
        price_cents: 7_900,
        stock: 31,
        rating: 4.7,
        reviews: 302,
        badge: "Travel pick",
        symbol: "✣",
        tone: "cyan",
        features: [ "100 W GaN output", "Four USB ports", "Universal plug system" ]
      ),
      Product.new(
        id: "mixpad-console",
        name: "Mixpad Creator Console",
        category: "studio",
        category_name: "Studio",
        description: "Tactile shortcuts, dials and scene controls for editing, streaming and live production.",
        price_cents: 23_900,
        stock: 11,
        rating: 4.5,
        reviews: 83,
        badge: nil,
        symbol: "⌘",
        tone: "lime",
        features: [ "Nine haptic dials", "Per-app profiles", "Open shortcut API" ]
      ),
      Product.new(
        id: "wave-microphone",
        name: "Wave Broadcast Microphone",
        category: "studio",
        category_name: "Studio",
        description: "A warm dynamic microphone with built-in USB preamp for speech, vocals and instruments.",
        price_cents: 14_900,
        stock: 19,
        rating: 4.7,
        reviews: 177,
        badge: "Bestseller",
        symbol: "♩",
        tone: "plum",
        features: [ "USB-C and XLR", "Zero-latency monitoring", "Desk stand included" ]
      )
    ].each do |product|
      product.features.each(&:freeze)
      product.to_h.each_value(&:freeze)
      product.freeze
    end.freeze

    def all
      PRODUCTS
    end

    def find(id)
      products_by_id[id.to_s]
    end

    def categories
      @categories ||= all.to_h { |product| [ product.category, product.category_name ] }.freeze
    end

    def search(query: nil, category: nil, max_price_cents: nil, in_stock: false, sort: "featured")
      products = all
      normalized_query = query.to_s.downcase.strip

      if normalized_query.present?
        products = products.select do |product|
          [ product.name, product.description, product.category_name, *product.features ]
            .any? { |value| value.downcase.include?(normalized_query) }
        end
      end

      products = products.select { |product| product.category == category } if category.present?
      products = products.select { |product| product.price_cents <= max_price_cents } if max_price_cents
      products = products.select(&:in_stock?) if in_stock

      case sort
      when "price_asc" then products.sort_by(&:price_cents)
      when "price_desc" then products.sort_by(&:price_cents).reverse
      when "rating" then products.sort_by { |product| [ -product.rating, -product.reviews ] }
      else products
      end
    end

    private

    def products_by_id
      @products_by_id ||= all.index_by(&:id).freeze
    end
  end
end
