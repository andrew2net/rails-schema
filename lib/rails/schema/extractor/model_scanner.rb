# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class ModelScanner
        def initialize(configuration: ::Rails::Schema.configuration, schema_data: nil)
          @configuration = configuration
          @schema_data = schema_data.nil? || schema_data.empty? ? nil : schema_data
        end

        def scan
          eager_load_models!

          all_descendants = ActiveRecord::Base.descendants
          non_abstract = all_descendants.reject(&:abstract_class?)
          named = non_abstract.reject { |m| m.name.nil? }
          with_tables = named.select { |m| table_known?(m) }
          included = with_tables.reject { |m| excluded?(m) }
          log_empty_scan(all_descendants, non_abstract, named, with_tables) if included.empty?

          included.sort_by(&:name)
        end

        private

        def eager_load_models!
          return unless defined?(::Rails.application) && ::Rails.application

          if defined?(::Rails.autoloaders) && ::Rails.autoloaders.respond_to?(:main)
            eager_load_via_zeitwerk!
          else
            eager_load_via_application!
          end
        end

        def eager_load_via_zeitwerk!
          loader = ::Rails.autoloaders.main
          dirs = model_directories
          dirs.each { |dir| loader.eager_load_dir(dir) } if dirs.any? && loader.respond_to?(:eager_load_dir)
          loader.eager_load if no_concrete_descendants?
        rescue StandardError, LoadError => e
          warn "[rails-schema] Zeitwerk eager_load failed (#{e.class}: #{e.message}), " \
               "trying Rails.application.eager_load!"
          eager_load_via_application!
        end

        def eager_load_via_application!
          ::Rails.application.eager_load!
        rescue StandardError, LoadError => e
          warn "[rails-schema] eager_load! failed (#{e.class}: #{e.message}), " \
               "falling back to per-file model loading"
          eager_load_model_files!
        end

        def eager_load_model_files!
          return unless defined?(::Rails.root) && ::Rails.root

          dirs = model_directories
          return if dirs.empty?

          dirs.flat_map { |d| Dir.glob(File.join(d, "**/*.rb")) }.sort.each do |file|
            require file
          rescue StandardError, LoadError => e
            warn "[rails-schema] Could not load #{file}: #{e.class}: #{e.message}"
          end
        end

        def model_directories
          dirs = PackwerkDiscovery.new.model_paths
          default_path = ::Rails.root&.join("app", "models")&.to_s
          dirs << default_path if default_path && !dirs.include?(default_path)
          dirs.select { |d| d && File.directory?(d) }.uniq
        end

        def no_concrete_descendants?
          ActiveRecord::Base.descendants.none? { |m| !m.abstract_class? && m.name }
        end

        def table_known?(model)
          @schema_data ? @schema_data.key?(model.table_name) : safe_table_exists?(model)
        end

        def safe_table_exists?(model)
          model.table_exists?
        rescue StandardError => e
          warn "[rails-schema] Could not check table for #{model.name}: #{e.class}: #{e.message}"
          false
        end

        def excluded?(model)
          return true if @configuration.exclude_model_if&.call(model)

          @configuration.exclude_models.any? do |pattern|
            pattern.end_with?("*") ? model.name.start_with?(pattern.delete_suffix("*")) : model.name == pattern
          end
        end

        def log_empty_scan(all_descendants, non_abstract, named, with_tables)
          return if all_descendants.empty?

          warn "[rails-schema] No models found! Filtering: " \
               "#{all_descendants.size} descendants → #{non_abstract.size} concrete → " \
               "#{named.size} named → #{with_tables.size} with tables"
        end
      end
    end
  end
end
