# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class ColumnReader
        def read(model)
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
