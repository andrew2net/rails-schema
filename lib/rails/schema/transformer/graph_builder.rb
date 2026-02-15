# frozen_string_literal: true

module Rails
  module Schema
    module Transformer
      class GraphBuilder
        def initialize(column_reader: Extractor::ColumnReader.new, association_reader: Extractor::AssociationReader.new)
          @column_reader = column_reader
          @association_reader = association_reader
        end

        def build(models)
          node_names = models.to_set(&:name)
          nodes = models.map { |m| build_node(m) }
          edges = models.flat_map { |m| build_edges(m, node_names) }

          {
            nodes: nodes.map(&:to_h),
            edges: edges.map(&:to_h),
            metadata: build_metadata(models)
          }
        end

        private

        def build_node(model)
          Node.new(
            id: model.name,
            table_name: model.table_name,
            columns: @column_reader.read(model)
          )
        end

        def build_edges(model, node_names)
          @association_reader.read(model).filter_map do |assoc|
            next unless node_names.include?(assoc[:to])

            Edge.new(
              from: assoc[:from],
              to: assoc[:to],
              association_type: assoc[:association_type],
              label: assoc[:label],
              foreign_key: assoc[:foreign_key],
              through: assoc[:through],
              polymorphic: assoc[:polymorphic]
            )
          end
        end

        def build_metadata(models)
          {
            generated_at: Time.now.utc.iso8601,
            model_count: models.size,
            rails_version: defined?(::Rails.version) ? ::Rails.version : nil
          }
        end
      end
    end
  end
end
