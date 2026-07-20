# frozen_string_literal: true

module SwiftUIRails
  class Engine < ::Rails::Engine
    isolate_namespace SwiftUIRails

    # NOTE: do not add the bare `SwiftUIRails` module to
    # `config.eager_load_namespaces`. It is a plain module with no
    # `eager_load!`, so under `config.eager_load = true` (production and CI)
    # Rails' eager-load initializer raises `NoMethodError: undefined method
    # 'eager_load!' for module SwiftUIRails`. The gem requires all of its own
    # code eagerly via `require_relative` at load time, so there is nothing to
    # eager-load lazily here.

    initializer "swift_ui_rails.assets" do |app|
      app.config.assets.precompile += %w[swift_ui_rails.js swift_ui_rails.css]
    end

    initializer "swift_ui_rails.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper SwiftUIRails::Helpers
      end
    end

    initializer "swift_ui_rails.view_component" do
      require "view_component"
    end
    
    config.after_initialize do
      # Include Tailwind modifiers if enabled
      if SwiftUIRails.configuration.tailwind_enabled
        SwiftUIRails::Component::Base.include(SwiftUIRails::Tailwind::Modifiers)
        # Element class was removed in our refactor
      end
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end
    
    # Load generators
    generators do
      require_relative "../generators/swift_ui_rails/install/install_generator"
      require_relative "../generators/swift_ui_rails/component/component_generator"
      require_relative "../generators/swift_ui_rails/stories/stories_generator"
    end
  end
end