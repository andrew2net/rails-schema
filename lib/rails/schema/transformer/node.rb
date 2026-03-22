# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class Node
        attr_reader :id, :table_name, :columns, :group

        def initialize(id:, table_name:, columns: [], group: [])
          @id = id
          @table_name = table_name
          @columns = columns
          @group = group
        end

        def to_h
          h = { id: @id, table_name: @table_name, columns: @columns }
          h[:group] = @group unless @group.empty?
          h
        end
      end
    end
  end
end
