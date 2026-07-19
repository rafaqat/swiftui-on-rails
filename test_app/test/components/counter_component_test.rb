# frozen_string_literal: true

require "test_helper"

class CounterComponentTest < ViewComponent::TestCase
  include SwiftUIRails::Helpers
  
  def test_renders_with_default_props
    render_inline(CounterComponent.new)
    
    assert_text "Counter: 0"
    assert_text "0" # The large count display
    assert_selector "button", text: "-"
    assert_selector "button", text: "Reset"
    assert_selector "button", text: "+"
  end
  
  def test_renders_with_custom_props
    render_inline(CounterComponent.new(
      initial_count: 10,
      step: 5,
      label: "My Counter"
    ))
    
    assert_text "My Counter: 10"
    assert_text "10"
  end
  
  def test_exposes_configuration_as_props_and_server_state
    component = CounterComponent.new(initial_count: 5, step: 2, label: "Cart")

    assert_equal 5, component.initial_count
    assert_equal 2, component.step
    assert_equal "Cart", component.label
    assert_equal 5, component.count
    assert_respond_to component, :count=
  end
  
  def test_generates_a_unique_dom_id_by_default
    first = CounterComponent.new
    second = CounterComponent.new

    assert_match(/\Acounter-[0-9a-f]{8}\z/, first.counter_id)
    refute_equal first.counter_id, second.counter_id
  end
  
  def test_observed_object_store
    # Create a shared store
    store = SwiftUIRails::Reactive::ObservableStore.find_or_create(:test_store)
    store.reset
    
    # Set some data
    store.set(:count, 42)
    assert_equal 42, store.get(:count)
    
    # Update data
    store.update do |data|
      data[:count] = 100
      data[:name] = "Test"
    end
    
    assert_equal 100, store.get(:count)
    assert_equal "Test", store.get(:name)
  end
  
  def test_wires_signed_ruby_actions_and_semantic_markers
    render_inline(CounterComponent.new)

    assert_selector "[data-counter-label='true']"
    assert_selector "[data-counter-display='true']"
    assert_selector "button[data-sui-actions]", count: 3
    assert_no_selector "[data-controller], [data-action]"
  end
  
  def test_places_initial_state_in_the_encrypted_component_snapshot
    render_inline(CounterComponent.new(initial_count: 7, step: 3, label: "Items"))

    assert_selector "[data-sui-root='1'] [data-counter='true']"
    assert_selector "[data-sui-snapshot]"
    assert_text "Items: 7"
  end
  
  def test_does_not_emit_a_second_client_state_model
    render_inline(CounterComponent.new)

    assert_no_selector "[data-controller], [data-action], [data-counter-target]"
  end
end
