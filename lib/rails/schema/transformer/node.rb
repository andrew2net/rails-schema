# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class Node
        attr_reader :id, :table_name, :columns

        def initialize(id:, table_name:, columns: [])
          @id = id
          @table_name = table_name
          @columns = columns
        end

        def to_h
          {
            id: @id,
            table_name: @table_name,
            columns: @columns
          }
        end
      end
    end
  end
end
