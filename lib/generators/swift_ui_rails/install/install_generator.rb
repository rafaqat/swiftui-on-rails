# frozen_string_literal: true

module SwiftUIRails
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/swift_ui_rails.rb"
      end

      def create_application_component
        template "application_component.rb", "app/components/application_component.rb"
      end

      def add_javascript
        application_path = File.join(destination_root, "app/javascript/application.js")
        unless File.exist?(application_path) && File.read(application_path).include?('import "swift_ui_runtime"')
          append_to_file "app/javascript/application.js" do
            <<~JS

              // SwiftUI Rails
              import "swift_ui_runtime"
            JS
          end
        end

        template "swift_ui_runtime.js", "app/javascript/swift_ui_runtime.js"
        template "swift_ui_render_patch.js", "app/javascript/swift_ui_render_patch.js"

        importmap_path = File.join(destination_root, "config/importmap.rb")
        if File.exist?(importmap_path) && !File.read(importmap_path).include?('pin "@rails/actioncable"')
          append_to_file "config/importmap.rb", <<~RUBY

            # SwiftUI Rails reactive observation
            pin "@rails/actioncable", to: "actioncable.esm.js"
          RUBY
        end
        if File.exist?(importmap_path) && !File.read(importmap_path).include?('pin "swift_ui_render_patch"')
          append_to_file "config/importmap.rb", <<~RUBY

            # SwiftUI Rails bounded RenderIR patch runtime
            pin "swift_ui_render_patch"
          RUBY
        end
        if File.exist?(importmap_path) && !File.read(importmap_path).include?('pin "swift_ui_runtime"')
          append_to_file "config/importmap.rb", <<~RUBY

            # SwiftUI Rails framework-free semantic DOM runtime
            pin "swift_ui_runtime"
          RUBY
        end
      end

      def add_reactive_endpoints
        template "swift_ui/actions_controller.rb", "app/controllers/swift_ui/actions_controller.rb"
        template "swift_ui/components_controller.rb", "app/controllers/swift_ui/components_controller.rb"

        route <<~RUBY
          namespace :swift_ui do
            resources :actions, only: [:create]
            post "components/update", to: "components#update_component", as: :component_update
          end
        RUBY
      end

      def add_styles
        legacy_tailwind_input = "app/assets/stylesheets/application.tailwind.css"
        if File.exist?(legacy_tailwind_input)
          append_to_file legacy_tailwind_input do
            <<~CSS
              
              /* SwiftUI Rails Components */
              @import "swift_ui_rails";
            CSS
          end
        end

        tailwind_input = [
          "app/assets/tailwind/application.css",
          legacy_tailwind_input
        ].find { |path| File.exist?(path) }

        if tailwind_input
          append_to_file tailwind_input, File.read(File.expand_path("templates/tailwind_sources.css", __dir__))
        end

        template "swift_ui_rails.css", "app/assets/stylesheets/swift_ui_rails.css"
      end

      def create_example_component
        template "example_component.rb", "app/components/example_component.rb"
      end

      def setup_storybook
        unless storybook_available?
          say <<~MESSAGE, :yellow

            Skipping ViewComponent Storybook setup because no compatible
            provider for `view_component/storybook` is installed. The core
            SwiftUI Rails runtime is fully installed; add the optional
            `view_component-storybook` gem and rerun this generator to install
            Storybook routes, configuration, styles, and the example story.
          MESSAGE
          return
        end

        # Create storybook directories
        empty_directory "test/components/stories"
        
        # Add storybook routes if not already present
        route_content = <<~RUBY
          if defined?(ViewComponent::Storybook::Engine)
            mount ViewComponent::Storybook::Engine, at: "/swift_ui/storybook"
          end
        RUBY
        
        route route_content
        
        # Create storybook configuration
        template "storybook_config.rb", "config/initializers/view_component_storybook.rb"
        
        # Add storybook CSS
        template "storybook.css", "app/assets/stylesheets/storybook.css"
        
        # Create example story
        template "example_component_stories.rb", "test/components/stories/example_component_stories.rb"
        # This is application ERB, not a generator interpolation template.
        copy_file "example_component_preview.html.erb", "test/components/stories/example_component_preview.html.erb"
      end

      def display_post_install_message
        say "\n✅ SwiftUI Rails has been successfully installed!", :green
        say "\nNext steps:", :yellow
        say "  1. Run 'bundle install' to install the gem dependencies"
        say "  2. Run 'rails generate swift_ui_rails:component MyComponent' to create new components"
        if storybook_available?
          say "  3. Run 'rails generate swift_ui_rails:stories MyComponent' to create component stories"
          say "  4. Visit http://localhost:3000/swift_ui/storybook to see the component storybook"
          say "  5. Visit http://localhost:3000/swift_ui_rails/demo to see examples"
        else
          say "  3. Optional: add a compatible `view_component-storybook` gem for component stories"
          say "  4. Visit http://localhost:3000/swift_ui_rails/demo to see examples"
        end
        say "\nHappy coding! 🚀\n", :blue
      end

      private

      def storybook_available?
        SwiftUIRails.storybook_available? || SwiftUIRails.load_storybook
      end
    end
  end
end
