# frozen_string_literal: true

module Rails
  module Schema
    class Configuration
      attr_accessor :output_path, :exclude_models, :exclude_model_if, :title, :theme, :expand_columns, :schema_format,
                    :model_schema_group, :collapse_groups, :show_through_edges

      def initialize
        @output_path = "docs/schema.html"
        @exclude_models = []
        @exclude_model_if = nil
        @title = "Database Schema"
        @theme = :auto
        @expand_columns = false
        @schema_format = :auto
        @model_schema_group = nil
        @collapse_groups = true
        @show_through_edges = true
      end

      def resolved_group_proc
        case @model_schema_group
        when nil then nil
        when :namespaces
          ->(model) { model.name.split("::")[0..-2] }
        when Proc then @model_schema_group
        else
          raise ArgumentError, "model_schema_group must be nil, :namespaces, or a Proc"
        end
      end
    end
  end
end
