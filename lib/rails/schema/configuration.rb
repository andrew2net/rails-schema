# frozen_string_literal: true

module Rails
  module Schema
    class Configuration
      attr_accessor :output_path, :exclude_models, :title, :theme, :expand_columns

      def initialize
        @output_path = "docs/schema.html"
        @exclude_models = []
        @title = "Database Schema"
        @theme = :auto
        @expand_columns = false
      end
    end
  end
end
