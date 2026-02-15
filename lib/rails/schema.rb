# frozen_string_literal: true

require_relative "schema/version"
require_relative "schema/configuration"
require_relative "schema/transformer/node"
require_relative "schema/transformer/edge"
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
        models = Extractor::ModelScanner.new.scan
        graph_data = Transformer::GraphBuilder.new.build(models)
        generator = Renderer::HtmlGenerator.new(graph_data: graph_data)
        generator.render_to_file(output)
      end
    end
  end
end

require_relative "schema/railtie" if defined?(Rails::Railtie)
