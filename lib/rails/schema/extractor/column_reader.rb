# frozen_string_literal: true

require "set"

module Rails
  module Schema
    module Extractor
      class ColumnReader
        def initialize(schema_data: nil, view_tables: nil)
          @schema_data = schema_data
          @view_tables = view_tables ? Set.new(view_tables) : Set.new
        end

        def read(model)
          if @view_tables.include?(model.table_name)
            read_view(model)
          elsif @schema_data&.key?(model.table_name)
            @schema_data[model.table_name]
          else
            read_from_model(model)
          end
        end

        private

        # Views have no column types in their DDL, so prefer live DB
        # introspection (accurate names + types) and fall back to the parsed
        # column names when no database connection is available.
        def read_view(model)
          from_db = read_from_model(model)
          return from_db unless from_db.empty?

          @schema_data&.fetch(model.table_name, []) || []
        end

        def read_from_model(model)
          model.columns.map do |col|
            {
              name: col.name,
              type: col.type.to_s,
              nullable: col.null,
              primary: col.name == model.primary_key,
              default: col.default
            }
          end
        rescue StandardError => e
          warn "[rails-schema] Could not read columns for #{model.name}: #{e.class}: #{e.message}"
          []
        end
      end
    end
  end
end
