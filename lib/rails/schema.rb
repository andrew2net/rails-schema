# frozen_string_literal: true

require_relative "schema/version"
require_relative "schema/configuration"
require_relative "schema/transformer/node"
require_relative "schema/transformer/edge"
require_relative "schema/extractor/schema_file_parser"
require_relative "schema/extractor/structure_sql_parser"
require_relative "schema/extractor/model_scanner"
require_relative "schema/extractor/column_reader"
require_relative "schema/extractor/association_reader"
require_relative "schema/transformer/graph_builder"
require_relative "schema/renderer/html_generator"

module Rails
  module Schema
    class Error < StandardError; end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      def generate(output: nil)
        schema_data = parse_schema
        models = Extractor::ModelScanner.new(schema_data: schema_data).scan
        column_reader = Extractor::ColumnReader.new(schema_data: schema_data)
        graph_data = Transformer::GraphBuilder.new(column_reader: column_reader).build(models)
        generator = Renderer::HtmlGenerator.new(graph_data: graph_data)
        generator.render_to_file(output)
      end

      private

      def parse_schema
        case configuration.schema_format
        when :ruby
          Extractor::SchemaFileParser.new.parse
        when :sql
          Extractor::StructureSqlParser.new.parse
        when :auto
          data = Extractor::SchemaFileParser.new.parse
          data.empty? ? Extractor::StructureSqlParser.new.parse : data
        end
      end
    end
  end
end

require_relative "schema/railtie" if defined?(Rails::Railtie)
