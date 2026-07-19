# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tmpdir"
require "generators/swift_ui_rails/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests SwiftUIRails::Generators::InstallGenerator
  destination Rails.root.join("tmp/install_generator")

  setup do
    FileUtils.mkdir_p(destination_root)
    @isolated_destination_root = Dir.mktmpdir("install-generator-test-", destination_root.to_s)
    self.destination_root = @isolated_destination_root
    prepare_destination
    FileUtils.mkdir_p File.join(destination_root, "app/javascript")
    FileUtils.mkdir_p File.join(destination_root, "app/assets/stylesheets")
    FileUtils.mkdir_p File.join(destination_root, "app/assets/tailwind")
    FileUtils.mkdir_p File.join(destination_root, "config")
    File.write File.join(destination_root, "app/javascript/application.js"), "import \"controllers\"\n"
    File.write File.join(destination_root, "config/importmap.rb"), "pin \"application\"\n"
    File.write File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n"
    File.write File.join(destination_root, "app/assets/tailwind/application.css"), "@import \"tailwindcss\";\n"
  end

  teardown do
    if @isolated_destination_root && File.exist?(@isolated_destination_root)
      FileUtils.remove_entry(@isolated_destination_root)
    end
  end

  test "installs the complete reactive browser and server runtime" do
    run_generator

    assert_file "app/javascript/swift_ui_runtime.js"
    assert_file "app/javascript/swift_ui_render_patch.js"
    assert_no_file "app/javascript/controllers/swift_ui_controller.js"
    assert_file "app/javascript/application.js" do |source|
      assert_includes source, 'import "swift_ui_runtime"'
      refute_includes source, 'import "./controllers/swift_ui_controller"'
    end

    assert_file "app/controllers/swift_ui/actions_controller.rb" do |source|
      assert_includes source, "SwiftUIRails::Reactive::ComponentActionsController"
      assert_nothing_raised { RubyVM::InstructionSequence.compile(source) }
    end
    assert_file "app/controllers/swift_ui/components_controller.rb" do |source|
      assert_includes source, "SwiftUIRails::Reactive::ReactiveController"
      assert_nothing_raised { RubyVM::InstructionSequence.compile(source) }
    end

    assert_file "config/routes.rb" do |source|
      assert_includes source, "namespace :swift_ui"
      assert_includes source, "resources :actions, only: [:create]"
      assert_includes source, 'post "components/update", to: "components#update_component"'
    end
    assert_file "config/importmap.rb" do |source|
      assert_includes source, 'pin "@rails/actioncable", to: "actioncable.esm.js"'
      assert_includes source, 'pin "swift_ui_render_patch"'
      assert_includes source, 'pin "swift_ui_runtime"'
    end
    assert_file "config/initializers/swift_ui_rails.rb" do |source|
      assert_includes source, 'config.allowed_components << "ExampleComponent"'
    end
    assert_file "app/components/example_component.rb" do |source|
      assert_includes source, "component.counter += 1"
      assert_includes source, ".text_style(:title)"
      assert_includes source, ".text_style(:supporting)"
      assert_includes source, ".button_style(:bordered_prominent)"
      assert_includes source, "card(elevation: 2).padding(6)"
      refute_includes source, 'class: "p-6"'
      refute_includes source, ".text_color("
      refute_includes source, ".text_size("
      assert_nothing_raised { RubyVM::InstructionSequence.compile(source) }
    end
    assert_file "app/assets/stylesheets/swift_ui_rails.css" do |source|
      assert_includes source, "prefers-reduced-motion: reduce"
      assert_includes source, "--swift-ui-foreground-primary"
      assert_includes source, ".swift-ui-font-headline"
      assert_includes source, '[data-swift-ui-theme="dark"]'
      assert_includes source, '[data-sui-enhanced="toolbar"]'
      assert_includes source, '[data-sui-toolbar-minimized="true"]'
      refute_includes source, "data-swift-ui-presentation-enhanced"
    end
    assert_file "app/assets/tailwind/application.css" do |source|
      assert_includes source, '@source inline("animate-spin auto-rows-fr'
      assert_includes source, "disabled:opacity-50"
      assert_includes source, "self-stretch"
    end
    assert_file "config/initializers/view_component_storybook.rb" do |source|
      assert_includes source, "include SwiftUIRails::Storybook::Helpers"
      refute_includes source, "include SwiftUIRails::Storybook if"
      assert_nothing_raised { RubyVM::InstructionSequence.compile(source) }
    end
    assert_file "test/components/stories/example_component_stories.rb"
  end

  test "installs the core runtime without generating broken Storybook files when the optional provider is absent" do
    SwiftUIRails.stub(:storybook_available?, false) do
      SwiftUIRails.stub(:load_storybook, false) { run_generator }
    end

    assert_file "app/components/example_component.rb"
    assert_no_file "config/initializers/view_component_storybook.rb"
    assert_no_file "test/components/stories/example_component_stories.rb"
    assert_no_file "app/assets/stylesheets/storybook.css"
    assert_file "config/routes.rb" do |source|
      refute_includes source, "ViewComponent::Storybook"
    end
  end

  test "packaged framework-free runtime matches the exercised test app runtime" do
    template = Rails.root.join("..", "lib/generators/swift_ui_rails/install/templates/swift_ui_runtime.js")
    runtime = Rails.root.join("app/javascript/swift_ui_runtime.js")
    assert_equal File.read(runtime), File.read(template), "semantic DOM runtime packaging drifted"

    patch_template = Rails.root.join("..", "lib/generators/swift_ui_rails/install/templates/swift_ui_render_patch.js")
    patch_runtime = Rails.root.join("app/javascript/swift_ui_render_patch.js")
    assert_equal File.read(patch_runtime), File.read(patch_template), "render patch runtime packaging drifted"
  end
end
