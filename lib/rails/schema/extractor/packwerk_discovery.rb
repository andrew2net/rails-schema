# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class PackwerkDiscovery
        def model_paths
          return [] unless defined?(::Rails.root) && ::Rails.root

          find_package_directories.flat_map do |dir|
            %w[app/models app/public].map { |sub| File.join(dir, sub) }
          end
        end

        private

        def find_package_directories
          patterns = package_paths
          return [] if patterns.empty?

          patterns.flat_map do |pattern|
            Dir.glob(::Rails.root.join(pattern).to_s).select do |path|
              File.directory?(path) && File.exist?(File.join(path, "package.yml"))
            end
          end
        end

        def package_paths
          packwerk_yml = ::Rails.root.join("packwerk.yml")
          return [] unless File.exist?(packwerk_yml)

          require "yaml"
          config = YAML.safe_load(File.read(packwerk_yml)) || {}
          config["package_paths"] || ["**/"]
        rescue StandardError
          []
        end
      end
    end
  end
end
