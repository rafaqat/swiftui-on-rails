# frozen_string_literal: true

module ViewComponent
  module Storybook
    module Controls
      class Control
        include ActiveModel::Validations

        validates :param, presence: true

        attr_reader :param, :name, :description, :default

        def initialize(param, default:, name: nil, description: nil)
          @param = param
          @default = default
          @name = name || param.to_s.humanize.titlecase
          @description = description
        end

        def to_csf_params
          # simplecov:disable
          raise NotImplementedError
          # simplecov:enable
        end

        def parse_param_value(value)
          # simplecov:disable
          raise NotImplementedError
          # simplecov:enable
        end
      end
    end
  end
end
