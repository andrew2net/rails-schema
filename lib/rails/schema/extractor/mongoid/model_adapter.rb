# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      module Mongoid
        class ModelAdapter
          attr_reader :model

          def initialize(model)
            @model = model
          end

          def name
            model.name
          end

          def table_name
            model.collection_name.to_s
          end

          def respond_to_missing?(method, include_private = false)
            model.respond_to?(method, include_private) || super
          end

          def method_missing(method, *args, **kwargs, &block)
            if model.respond_to?(method)
              model.send(method, *args, **kwargs, &block)
            else
              super
            end
          end
        end
      end
    end
  end
end
