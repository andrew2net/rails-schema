# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class Edge
        attr_reader :from, :to, :association_type, :label, :foreign_key, :through, :polymorphic

        def initialize(from:, to:, association_type:, label:, foreign_key: nil, through: nil, polymorphic: false)
          @from = from
          @to = to
          @association_type = association_type
          @label = label
          @foreign_key = foreign_key
          @through = through
          @polymorphic = polymorphic
        end

        def to_h
          {
            from: @from,
            to: @to,
            association_type: @association_type,
            label: @label,
            foreign_key: @foreign_key,
            through: @through,
            polymorphic: @polymorphic
          }
        end
      end
    end
  end
end
