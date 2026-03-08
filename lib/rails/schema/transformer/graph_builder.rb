# frozen_string_literal: true

require "set"

module Rails
  module Schema
    module Transformer
      class GraphBuilder
        def initialize(column_reader: Extractor::ColumnReader.new, association_reader: Extractor::AssociationReader.new)
          @column_reader = column_reader
          @association_reader = association_reader
        end

        def build(models)
          model_ids = assign_unique_ids(models)
          name_to_id = {}
          model_ids.each { |m, uid| name_to_id[m.name] ||= uid }

          nodes = model_ids.map { |m, uid| build_node(m, uid) }
          edges = model_ids.flat_map { |m, uid| build_edges(m, uid, name_to_id) }

          {
            nodes: nodes.map(&:to_h),
            edges: edges.map(&:to_h),
            metadata: build_metadata(models)
          }
        end

        private

        def assign_unique_ids(models)
          counts = models.group_by(&:name).transform_values(&:size)
          models.map do |m|
            uid = counts[m.name] > 1 ? "#{m.name} (#{m.table_name})" : m.name
            [m, uid]
          end
        end

        def build_node(model, unique_id)
          Node.new(
            id: unique_id,
            table_name: model.table_name,
            columns: @column_reader.read(model)
          )
        end

        def build_edges(model, unique_id, name_to_id)
          @association_reader.read(model).filter_map do |assoc|
            next unless name_to_id.key?(assoc[:to])

            Edge.new(
              from: unique_id,
              to: name_to_id[assoc[:to]],
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
