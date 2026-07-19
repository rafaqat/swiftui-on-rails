# frozen_string_literal: true

require "test_helper"

class SwiftUIRails::RenderIRPerformanceTest < ActiveSupport::TestCase
  NODE_COUNT = 1_000
  SAMPLE_COUNT = 5
  MAX_IR_CPU_SECONDS = 0.1
  MAX_CPU_RATIO = 8.0
  MAX_IR_ALLOCATIONS = 80_000
  MAX_ALLOCATION_RATIO = 6.0

  test "one-pass RenderIR stays within the flat-tree performance budget" do
    Rails.logger.silence(Logger::WARN) do
      ir_warmup = measure_flush(:render_ir)
      legacy_warmup = measure_flush(:legacy)
      assert_equal legacy_warmup.fetch(:html), ir_warmup.fetch(:html)

      ir = median_sample(:render_ir)
      legacy = median_sample(:legacy)
      cpu_ratio = ir.fetch(:cpu).fdiv(legacy.fetch(:cpu))
      allocation_ratio = ir.fetch(:allocations).fdiv(legacy.fetch(:allocations))
      diagnostics = performance_diagnostics(ir, legacy, cpu_ratio, allocation_ratio)

      assert_operator ir.fetch(:cpu), :<, MAX_IR_CPU_SECONDS, diagnostics
      assert_operator cpu_ratio, :<, MAX_CPU_RATIO, diagnostics
      assert_operator ir.fetch(:allocations), :<, MAX_IR_ALLOCATIONS, diagnostics
      assert_operator allocation_ratio, :<, MAX_ALLOCATION_RATIO, diagnostics
    end
  end

  private

  def median_sample(renderer)
    samples = Array.new(SAMPLE_COUNT) { measure_flush(renderer) }
    {
      cpu: median(samples.map { |sample| sample.fetch(:cpu) }),
      allocations: median(samples.map { |sample| sample.fetch(:allocations) })
    }
  end

  def median(values)
    sorted = values.sort
    sorted.fetch(sorted.length / 2)
  end

  def measure_flush(renderer)
    context = build_context
    GC.start
    allocations_before = GC.stat(:total_allocated_objects)
    started_at = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    html = renderer == :render_ir ? context.flush_elements : legacy_flush(context)
    cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - started_at

    {
      cpu: cpu,
      allocations: GC.stat(:total_allocated_objects) - allocations_before,
      html: html
    }
  end

  def build_context
    SwiftUIRails::DSLContext.new(render_view).tap do |context|
      context.instance_eval do
        NODE_COUNT.times { |index| text("Item #{index}") }
      end
    end
  end

  # Invoke the pre-RenderIR owner chain without altering the production class.
  # InteractionElement#to_s delegates to the original Element#to_s implementation.
  def legacy_flush(context)
    elements = context.instance_variable_get(:@pending_elements)
    parts = elements.map do |element|
      element.view_context ||= context.view_context
      (legacy_element_renderer.bind_call(element) || "").html_safe
    end
    elements.clear
    context.safe_join(parts)
  end

  def legacy_element_renderer
    @legacy_element_renderer ||= begin
      candidate = SwiftUIRails::DSL::Element.instance_method(:to_s)
      candidate = candidate.super_method until candidate.owner == SwiftUIRails::DSL::InteractionElement
      candidate
    end
  end

  def render_view
    ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
  end

  def performance_diagnostics(ir, legacy, cpu_ratio, allocation_ratio)
    format(
      "RenderIR %.6fs/%d allocations; legacy %.6fs/%d allocations; ratios %.2fx/%.2fx",
      ir.fetch(:cpu),
      ir.fetch(:allocations),
      legacy.fetch(:cpu),
      legacy.fetch(:allocations),
      cpu_ratio,
      allocation_ratio
    )
  end
end
