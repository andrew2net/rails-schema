# frozen_string_literal: true

module Rails
  module Schema
    class Configuration
      attr_accessor :output_path, :exclude_models, :exclude_model_if, :title, :theme, :expand_columns, :schema_format

      def initialize
        @output_path = "docs/schema.html"
        @exclude_models = []
        @exclude_model_if = nil
        @title = "Database Schema"
        @theme = :auto
        @expand_columns = false
        @schema_format = :auto
      end
    end
  end
end
