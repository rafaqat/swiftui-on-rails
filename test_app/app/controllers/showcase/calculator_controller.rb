# frozen_string_literal: true

module Showcase
  class CalculatorController < ApplicationController
    SESSION_KEY = :showcase_calculator_state

    before_action :load_calculator

    def show; end

    def key
      key = params[:key].to_s
      return reject_invalid_key unless Calculator.valid_key?(key)

      @calculator.press(key)
      session[SESSION_KEY] = @calculator.to_h

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "showcase_calculator",
            partial: "showcase/calculator/calculator",
            locals: { calculator: @calculator }
          )
        end
        format.html { redirect_to showcase_calculator_path, status: :see_other }
      end
    end

    private

    def load_calculator
      @calculator = Calculator.from_state(session[SESSION_KEY])
    end

    def reject_invalid_key
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { head :unprocessable_entity }
      end
    end
  end
end
