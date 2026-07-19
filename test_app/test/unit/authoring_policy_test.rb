# frozen_string_literal: true

require "test_helper"

class AuthoringPolicyTest < ActiveSupport::TestCase
  PROMPT_PATH = Rails.root.join("../CLAUDE.md")
  FORBIDDEN_LLM_GUIDANCE = {
    /\.stimulus_(?:controller|action|target|param)\s*\(/ => "Stimulus modifier example",
    /\.data\(\s*controller:/ => "controller metadata example",
    %r{app/javascript/controllers/} => "application controller path",
    /import\s+\{\s*Controller\s*\}.*@hotwired\/stimulus/ => "Stimulus import",
    /state lives in stimulus/i => "client-owned state instruction"
  }.freeze

  test "checked-in LLM instructions enforce the Ruby and RenderIR model" do
    prompt = PROMPT_PATH.read

    assert_includes prompt, "## The one cognitive model"
    assert_includes prompt, "Ruby plus RenderIR is the complete application programming model."
    assert_includes prompt, "Do not create application JavaScript controllers"
    assert_includes prompt, "LanguageCatalog.for_generation"

    FORBIDDEN_LLM_GUIDANCE.each do |pattern, label|
      refute_match pattern, prompt, "CLAUDE.md contains a forbidden #{label}"
    end
  end
end
