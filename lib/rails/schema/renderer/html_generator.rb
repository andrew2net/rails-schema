# frozen_string_literal: true

require "erb"
require "json"
require "fileutils"

module Rails
  module Schema
    module Renderer
      class HtmlGenerator
        ASSETS_DIR = File.expand_path("../../schema/assets", __dir__)

        def initialize(graph_data:, configuration: ::Rails::Schema.configuration)
          @graph_data = graph_data
          @configuration = configuration
        end

        def render
          template = File.read(File.join(ASSETS_DIR, "template.html.erb"))
          erb = ERB.new(template)
          erb.result(binding)
        end

        def render_to_file(path = nil)
          path ||= @configuration.output_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, render)
          path
        end

        private

        def title
          @configuration.title
        end

        def theme_class
          case @configuration.theme
          when :light then "light"
          when :dark then "dark"
          else ""
          end
        end

        def css_content
          File.read(File.join(ASSETS_DIR, "style.css"))
        end

        def d3_js_content
          File.read(File.join(ASSETS_DIR, "vendor", "d3.min.js"))
        end

        def app_js_content
          File.read(File.join(ASSETS_DIR, "app.js"))
        end

        def graph_json
          JSON.generate(@graph_data).gsub("</", '<\/')
        end

        def config_json
          config = {
            expand_columns: @configuration.expand_columns,
            theme: @configuration.theme.to_s
          }
          JSON.generate(config).gsub("</", '<\/')
        end
      end
    end
  end
end
