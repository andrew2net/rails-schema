# frozen_string_literal: true

require "set"

module Rails
  module Schema
    module Transformer
      class GraphBuilder
        def initialize(column_reader: Extractor::ColumnReader.new, association_reader: Extractor::AssociationReader.new,
                       configuration: ::Rails::Schema.configuration)
          @column_reader = column_reader
          @association_reader = association_reader
          @group_proc = configuration.resolved_group_proc
        end

        def build(models)
          model_ids = assign_unique_ids(models)
          name_to_id = build_name_to_id(model_ids)

          nodes = model_ids.map { |m, uid| build_node(m, uid) }
          edges = deduplicate_edges(model_ids.flat_map { |m, uid| build_edges(m, uid, name_to_id) })

          {
            nodes: nodes.map(&:to_h),
            edges: edges.map(&:to_h),
            metadata: build_metadata(models)
          }
        end

        private

        def build_name_to_id(model_ids)
          model_ids.each_with_object({}) { |(m, uid), map| map[m.name] ||= uid }
        end

        def assign_unique_ids(models)
          counts = models.group_by(&:name).transform_values(&:size)
          models.map do |m|
            uid = counts[m.name] > 1 ? "#{m.name} (#{m.table_name})" : m.name
            [m, uid]
          end
        end

        def build_node(model, unique_id)
          group = @group_proc ? Array(@group_proc.call(model)) : []
          Node.new(
            id: unique_id,
            table_name: model.table_name,
            columns: @column_reader.read(model),
            group: group
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

        def deduplicate_edges(edges)
          edges = deduplicate_habtm(edges)
          deduplicate_has_many_belongs_to(edges)
        end

        def deduplicate_habtm(edges)
          habtm_first = {}

          edges.each_with_object([]) do |edge, result|
            next result << edge unless edge.association_type == "has_and_belongs_to_many"

            pair = [edge.from, edge.to].sort
            if habtm_first.key?(pair)
              habtm_first[pair].reverse_label = edge.label
            else
              habtm_first[pair] = edge
              result << edge
            end
          end
        end

        def deduplicate_has_many_belongs_to(edges)
          hm_lookup = build_has_many_lookup(edges)

          edges.each_with_object([]) do |edge, result|
            if edge.association_type == "belongs_to"
              hm_edge = hm_lookup[[edge.from, edge.to, edge.foreign_key]]
              if hm_edge
                hm_edge.reverse_label = edge.label
                hm_edge.reverse_association_type = edge.association_type
                next
              end
            end
            result << edge
          end
        end

        def build_has_many_lookup(edges)
          edges.each_with_object({}) do |edge, lookup|
            next unless %w[has_many has_one].include?(edge.association_type)

            lookup[[edge.to, edge.from, edge.foreign_key]] = edge
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
