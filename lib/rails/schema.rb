# frozen_string_literal: true

require_relative "schema/version"
require_relative "schema/configuration"
require_relative "schema/transformer/node"
require_relative "schema/transformer/edge"
require_relative "schema/extractor/schema_file_parser"
require_relative "schema/extractor/structure_sql_parser"
require_relative "schema/extractor/packwerk_discovery"
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
        if mongoid_mode?
          generate_mongoid(output: output)
        else
          generate_active_record(output: output)
        end
      end

      def mongoid_mode?
        case configuration.schema_format
        when :mongoid
          true
        when :auto
          defined?(::Mongoid::Document) ? true : false
        else
          false
        end
      end

      private

      def generate_active_record(output:)
        schema_data, views = parse_schema
        models = Extractor::ModelScanner.new(schema_data: schema_data).scan
        column_reader = Extractor::ColumnReader.new(schema_data: schema_data, view_tables: views)
        graph_data = Transformer::GraphBuilder.new(column_reader: column_reader, view_tables: views).build(models)
        graph_data[:metadata][:mode] = "active_record"
        generator = Renderer::HtmlGenerator.new(graph_data: graph_data)
        generator.render_to_file(output)
      end

      def require_mongoid_extractors
        require_relative "schema/extractor/mongoid/model_scanner"
        require_relative "schema/extractor/mongoid/model_adapter"
        require_relative "schema/extractor/mongoid/column_reader"
        require_relative "schema/extractor/mongoid/association_reader"
      end

      def generate_mongoid(output:)
        require_mongoid_extractors

        raw_models = Extractor::Mongoid::ModelScanner.new.scan
        models = raw_models.map { |m| Extractor::Mongoid::ModelAdapter.new(m) }
        column_reader = Extractor::Mongoid::ColumnReader.new
        association_reader = Extractor::Mongoid::AssociationReader.new
        graph_data = Transformer::GraphBuilder.new(
          column_reader: column_reader,
          association_reader: association_reader
        ).build(models)
        graph_data[:metadata][:mode] = "mongoid"
        generator = Renderer::HtmlGenerator.new(graph_data: graph_data)
        generator.render_to_file(output)
      end

      # Returns [columns_by_table, view_table_names]. For :auto, falls through
      # to structure.sql when schema.rb yields nothing.
      def parse_schema
        case configuration.schema_format
        when :ruby
          parse_with(Extractor::SchemaFileParser.new)
        when :sql
          parse_with(Extractor::StructureSqlParser.new)
        when :auto
          columns, views = parse_with(Extractor::SchemaFileParser.new)
          columns.empty? ? parse_with(Extractor::StructureSqlParser.new) : [columns, views]
        end
      end

      def parse_with(parser)
        columns = parser.parse
        [columns, parser.views]
      end
    end
  end
end

require_relative "schema/railtie" if defined?(Rails::Railtie)
