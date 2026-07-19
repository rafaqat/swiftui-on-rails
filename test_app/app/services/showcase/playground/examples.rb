# frozen_string_literal: true

module Showcase
  module Playground
    class Examples
      Example = Struct.new(:id, :name, :description, :source, :data_json, keyword_init: true)

      PRODUCT_CATALOG_SOURCE = <<~'RUBY'.freeze
        vstack(alignment: :leading, spacing: 18) do
          hstack(spacing: 12) do
            vstack(alignment: :leading, spacing: 2) do
              text(data[:store][:name])
                .text_style(:title)
              text(data[:store][:tagline])
                .text_style(:supporting)
            end
            spacer
            badge("#{data[:products].length} products", tone: :info)
          end

          grid(columns: 2, spacing: 16) do
            for_each(data[:products], id: "id") do |product|
              article do
                vstack(alignment: :leading, spacing: 10) do
                  icon(product[:icon], size: 28)
                    .foreground_style(product[:accent_role])
                  text(product[:name])
                    .text_style(:headline)
                  text(product[:description])
                    .text_style(:supporting)
                  hstack(spacing: 8) do
                    text("$#{product[:price]}")
                      .font(:headline)
                    spacer
                    if product[:in_stock]
                      badge("In Stock", tone: :success)
                    else
                      badge("Sold Out", tone: :danger)
                    end
                  end
                  button("Inspect")
                    .button_style(:bordered)
                    .button_size(:small)
                end
              end
                .padding(5)
                .background_style(:surface)
                .rounded("2xl")
                .shadow("sm")
            end
          end
        end
          .padding(6)
          .background_style(:canvas)
          .rounded("3xl")
      RUBY

      PRODUCT_CATALOG_DATA = <<~JSON.freeze
        {
          "store": {
            "name": "Northstar Supply",
            "tagline": "Field-tested tools for ambitious teams"
          },
          "products": [
            {
              "id": "trail-lamp",
              "name": "Trail Lamp",
              "description": "A compact, weather-sealed light with a 40-hour battery.",
              "price": 89,
              "in_stock": true,
              "icon": "bolt",
              "accent_role": "warning"
            },
            {
              "id": "field-radio",
              "name": "Field Radio",
              "description": "Encrypted team comms in a pocket-sized aluminium body.",
              "price": 249,
              "in_stock": false,
              "icon": "mail",
              "accent_role": "accent"
            },
            {
              "id": "survey-watch",
              "name": "Survey Watch",
              "description": "Offline maps, health telemetry, and precise waypoint capture.",
              "price": 319,
              "in_stock": true,
              "icon": "clock",
              "accent_role": "success"
            }
          ]
        }
      JSON

      MISSION_SOURCE = <<~'RUBY'.freeze
        vstack(alignment: :leading, spacing: 20) do
          hstack(spacing: 10) do
            icon("bolt", size: 30).foreground_style(:accent)
            vstack(alignment: :leading, spacing: 2) do
              text(data[:mission][:name]).text_style(:title)
              text(data[:mission][:phase]).text_style(:supporting)
            end
            spacer
            if data[:mission][:go]
              badge("GO FOR LAUNCH", tone: :success, announce: true)
            else
              badge("HOLD", tone: :warning, announce: true)
            end
          end

          section do
            vstack(alignment: :leading, spacing: 10) do
              text("Readiness").text_style(:headline)
              progress_view(value: data[:mission][:readiness], total: 100, label: "Mission readiness")
                .w_full
              hstack(spacing: 14) do
                gauge(value: data[:telemetry][:fuel], label: "Fuel")
                gauge(value: data[:telemetry][:link], label: "Link")
                gauge(value: data[:telemetry][:weather], label: "Weather")
              end
            end
          end
            .padding(5)
            .background_style(:muted)
            .rounded("2xl")

          vstack(alignment: :leading, spacing: 8) do
            text("Flight checks").text_style(:headline)
            for_each(data[:checks], id: "id") do |check|
              hstack(spacing: 10) do
                if check[:ready]
                  icon("check", size: 18).foreground_style(:success)
                else
                  icon("warning", size: 18).foreground_style(:warning)
                end
                text(check[:name])
                spacer
                text(check[:owner]).text_style(:metadata)
              end
                .padding(3)
                .background_style(:surface)
                .rounded("xl")
            end
          end
        end
          .padding(6)
      RUBY

      MISSION_DATA = <<~JSON.freeze
        {
          "mission": { "name": "Atlas VII", "phase": "T−00:12:42 · Terminal count", "readiness": 86, "go": true },
          "telemetry": { "fuel": 94, "link": 99, "weather": 78 },
          "checks": [
            { "id": "propulsion", "name": "Propulsion", "owner": "Chen", "ready": true },
            { "id": "guidance", "name": "Guidance", "owner": "Mbeki", "ready": true },
            { "id": "range", "name": "Range safety", "owner": "Reyes", "ready": false }
          ]
        }
      JSON

      TEAM_SOURCE = <<~'RUBY'.freeze
        vstack(alignment: :leading, spacing: 16) do
          hstack(spacing: 10) do
            vstack(alignment: :leading, spacing: 2) do
              text(data[:sprint][:title]).text_style(:title)
              text("#{data[:team].length} contributors · #{data[:sprint][:days_left]} days left")
                .text_style(:supporting)
            end
            spacer
            badge(data[:sprint][:status], tone: :info)
          end

          progress_view(value: data[:sprint][:complete], total: 100, label: "Sprint completion")
            .w_full

          grid(columns: 2, spacing: 12) do
            for_each(data[:team], id: "id") do |person|
              article do
                hstack(spacing: 10) do
                  icon("circle", size: 22).foreground_style(person[:accent_role])
                  vstack(alignment: :leading, spacing: 2) do
                    text(person[:name]).text_style(:headline)
                    text(person[:role]).text_style(:metadata)
                  end
                  spacer
                  if person[:blocked]
                    badge("Blocked", tone: :danger)
                  else
                    badge("On track", tone: :success)
                  end
                end
              end
                .padding(4)
                .background_style(:surface)
                .rounded("2xl")
            end
          end
        end
          .padding(6)
          .background_style(:canvas)
          .rounded("3xl")
      RUBY

      TEAM_DATA = <<~JSON.freeze
        {
          "sprint": { "title": "Release Candidate", "days_left": 4, "complete": 72, "status": "IN REVIEW" },
          "team": [
            { "id": "maya", "name": "Maya Chen", "role": "Interface systems", "blocked": false, "accent_role": "accent" },
            { "id": "theo", "name": "Theo Martin", "role": "Runtime", "blocked": false, "accent_role": "secondary" },
            { "id": "amina", "name": "Amina Diallo", "role": "Accessibility", "blocked": true, "accent_role": "warning" },
            { "id": "lucas", "name": "Lucas Silva", "role": "Developer tools", "blocked": false, "accent_role": "success" }
          ]
        }
      JSON

      ALL = [
        Example.new(id: "product-catalog", name: "Product catalog", description: "Conditional badges, fixture loops, cards, and semantic styling.", source: PRODUCT_CATALOG_SOURCE, data_json: PRODUCT_CATALOG_DATA),
        Example.new(id: "mission-readiness", name: "Mission readiness", description: "Progress, gauges, nested composition, and operational state.", source: MISSION_SOURCE, data_json: MISSION_DATA),
        Example.new(id: "team-sprint", name: "Team sprint", description: "A data-driven planning surface with conditional status.", source: TEAM_SOURCE, data_json: TEAM_DATA)
      ].each(&:freeze).freeze

      class << self
        def all
          ALL
        end

        def find(id)
          ALL.find { |example| example.id == id.to_s } || ALL.first
        end
      end
    end
  end
end
