# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class Node
        attr_reader :id, :table_name, :columns, :group, :view

        def initialize(id:, table_name:, columns: [], group: [], view: false)
          @id = id
          @table_name = table_name
          @columns = columns
          @group = group
          @view = view
        end

        def to_h
          h = { id: @id, table_name: @table_name, columns: @columns }
          h[:group] = @group unless @group.empty?
          h[:view] = true if @view
          h
        end
      end
    end
  end
end
