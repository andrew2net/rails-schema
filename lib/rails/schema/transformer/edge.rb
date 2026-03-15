# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class Edge
        attr_reader :from, :to, :association_type, :label, :foreign_key, :through, :polymorphic
        attr_accessor :reverse_label, :reverse_association_type

        def initialize(from:, to:, association_type:, label:, foreign_key: nil, through: nil, polymorphic: false)
          @from = from
          @to = to
          @association_type = association_type
          @label = label
          @foreign_key = foreign_key
          @through = through
          @polymorphic = polymorphic
          @reverse_label = nil
          @reverse_association_type = nil
        end

        def to_h
          {
            from: @from,
            to: @to,
            association_type: @association_type,
            label: @label,
            foreign_key: @foreign_key,
            through: @through,
            polymorphic: @polymorphic,
            reverse_label: @reverse_label,
            reverse_association_type: @reverse_association_type
          }
        end
      end
    end
  end
end
