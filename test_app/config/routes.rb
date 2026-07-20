Rails.application.routes.draw do
  # Custom interactive storybook routes
  get "rails/stories" => "storybook#index"
  get "rails/stories/:story" => "storybook#show", as: :story
  # Route-backed progressive-enhancement demo for portable WWDC26 workflows.
  patch "workflow_demo/reorder", to: "workflow_demo#reorder", as: :workflow_demo_reorder
  patch "workflow_demo/messages/:message/:workflow_action", to: "workflow_demo#message_action",
        constraints: { message: /roadmap|incident/, workflow_action: /archive|delete/ },
        as: :workflow_demo_message_action
  delete "workflow_demo/messages/:message/:workflow_action", to: "workflow_demo#message_action",
         constraints: { message: /roadmap|incident/, workflow_action: /archive|delete/ }
  post "workflow_demo/documents/import", to: "workflow_demo#import_document", as: :workflow_demo_document_import
  post "workflow_demo/documents", to: "workflow_demo#create_document", as: :workflow_demo_documents
  get "workflow_demo/documents/export", to: "workflow_demo#export_document", as: :workflow_demo_document_export
  
  # Legacy storybook routes
  get "storybook/index"
  get "storybook/show"
  
  # SwiftUI Rails action handling
  namespace :swift_ui do
    resources :actions, only: [:create]
    post "components/update", to: "components#update_component", as: :component_update
  end
  
  
  # Interactive demo gallery — each demo owns one interaction model.
  get "demos", to: "demos#index", as: :demos

  namespace :demos do
    get "ledger", to: "ledger#show", as: :ledger

    get "flightplan", to: "flightplan#show", as: :flightplan
    patch "flightplan/cards/:card/move", to: "flightplan#move",
          constraints: { card: /[a-z0-9\-]+/ }, as: :flightplan_card_move
    post "flightplan/reset", to: "flightplan#reset", as: :flightplan_reset

    get "pulse", to: "pulse#show", as: :pulse
    get "pulse/tick", to: "pulse#tick", as: :pulse_tick

    get "aperture", to: "aperture#show", as: :aperture

    get "preferences", to: "preferences#show", as: :preferences

    get "onboard", to: "onboard#show", as: :onboard
    post "onboard/advance", to: "onboard#advance", as: :onboard_advance
    post "onboard/reset", to: "onboard#reset", as: :onboard_reset

    get "dispatch", to: "dispatch#show", as: :dispatch

    get "relay", to: "relay#show", as: :relay
    post "relay/send", to: "relay#send_message", as: :relay_send
    patch "relay/archive", to: "relay#archive", as: :relay_archive
    post "relay/reset", to: "relay#reset", as: :relay_reset

    get "motion", to: "motion#show", as: :motion
    post "motion/bump", to: "motion#bump", as: :motion_bump
    post "motion/burst", to: "motion#burst", as: :motion_burst
    post "motion/shuffle", to: "motion#shuffle", as: :motion_shuffle
    post "motion/reveal", to: "motion#reveal", as: :motion_reveal
    post "motion/reset", to: "motion#reset", as: :motion_reset
  end

  # Stateless components demo
  get "stateless_demo", to: "stateless_demo#index"
  
  # Rails-first patterns demo
  get "rails_first_demo", to: "rails_first_demo#index"
  post "rails_first_demo/increment_counter", to: "rails_first_demo#increment_counter"
  post "rails_first_demo/add_todo", to: "rails_first_demo#add_todo"
  patch "rails_first_demo/todos/:id/toggle", to: "rails_first_demo#toggle_todo", as: :toggle_rails_first_demo_todo
  patch "rails_first_demo/todos/:id", to: "rails_first_demo#update_todo", as: :update_rails_first_demo_todo
  delete "rails_first_demo/delete_todo/:id", to: "rails_first_demo#delete_todo", as: :delete_todo
  post "rails_first_demo/search", to: "rails_first_demo#search"

  # Flagship showcase applications
  get "showcase/playground", to: "showcase/playground#show", as: :showcase_playground
  post "showcase/playground/run", to: "showcase/playground#run", as: :showcase_playground_run
  get "showcase/playground/preview", to: "showcase/playground#preview", as: :showcase_playground_preview
  post "showcase/playground/compile", to: "showcase/playground#compile", as: :showcase_playground_compile
  get "showcase/playground/language", to: "showcase/playground#language", as: :showcase_playground_language
  post "showcase/playground/assist", to: "showcase/playground#assist", as: :showcase_playground_assist
  post "showcase/playground/verify", to: "showcase/playground#verify", as: :showcase_playground_verify
  get "showcase/playground/reliability", to: "showcase/playground#reliability", as: :showcase_playground_reliability

  get "showcase/calculator", to: "showcase/calculator#show", as: :showcase_calculator
  post "showcase/calculator/key", to: "showcase/calculator#key", as: :showcase_calculator_key

  get "showcase/commerce", to: "showcase/commerce#show", as: :showcase_commerce
  get "showcase/commerce/products/:id", to: "showcase/commerce#product", as: :showcase_commerce_product
  post "showcase/commerce/cart", to: "showcase/commerce#add_to_cart", as: :showcase_commerce_cart_items
  patch "showcase/commerce/cart/:id", to: "showcase/commerce#update_cart", as: :showcase_commerce_cart_item
  delete "showcase/commerce/cart/:id", to: "showcase/commerce#remove_from_cart"
  post "showcase/commerce/checkout", to: "showcase/commerce#checkout", as: :showcase_commerce_checkout

  get "showcase/operations", to: "showcase/operations#show", as: :showcase_operations
  post "showcase/operations/events", to: "showcase/operations#event", as: :showcase_operations_events

  get "showcase/mission-control", to: "showcase/mission_control#show", as: :showcase_mission_control
  patch "showcase/mission-control/sequence", to: "showcase/mission_control#reorder",
        as: :showcase_mission_control_sequence
  patch "showcase/mission-control/systems/:system/:mission_action",
        to: "showcase/mission_control#system_action",
        constraints: {
          system: /propulsion|guidance|communications|range/,
          mission_action: /go|hold/
        },
        as: :showcase_mission_control_system_action
  patch "showcase/mission-control/alerts/:alert/:mission_action",
        to: "showcase/mission_control#alert_action",
        constraints: {
          alert: /winds|handoff/,
          mission_action: /acknowledge|escalate/
        },
        as: :showcase_mission_control_alert_action
  post "showcase/mission-control/advance", to: "showcase/mission_control#advance",
       as: :showcase_mission_control_advance
  post "showcase/mission-control/reset", to: "showcase/mission_control#reset",
       as: :showcase_mission_control_reset
  post "showcase/mission-control/documents/import", to: "showcase/mission_control#import_document",
       as: :showcase_mission_control_document_import
  post "showcase/mission-control/documents", to: "showcase/mission_control#create_document",
       as: :showcase_mission_control_documents
  get "showcase/mission-control/documents/export", to: "showcase/mission_control#export_document",
      as: :showcase_mission_control_document_export

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Component showcase routes
  get "counter", to: "home#counter", as: :counter
  
  # Product layout examples
  resources :products, only: [:index] do
    collection do
      get :catalog
    end
  end
  
  # Defines the root path route ("/")
  root "home#index"
end
