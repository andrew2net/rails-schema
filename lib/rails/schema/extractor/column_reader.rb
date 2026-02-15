# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class ColumnReader
        def initialize(schema_data: nil)
          @schema_data = schema_data
        end

        def read(model)
          if @schema_data&.key?(model.table_name)
            @schema_data[model.table_name]
          else
            read_from_model(model)
          end
        end

        private

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
        rescue StandardError
          []
        end
      end
    end
  end
end
