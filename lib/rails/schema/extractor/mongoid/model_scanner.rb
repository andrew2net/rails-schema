# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      module Mongoid
        class ModelScanner
          def initialize(configuration: ::Rails::Schema.configuration)
            @configuration = configuration
          end

          def scan
            eager_load_models!

            candidates = ObjectSpace.each_object(Class).select do |klass|
              klass.include?(::Mongoid::Document)
            rescue StandardError
              false
            end

            named = candidates.reject { |m| m.name.nil? }
            included = named.reject { |m| excluded?(m) }

            included.sort_by(&:name)
          end

          private

          def eager_load_models!
            return unless defined?(::Rails.application) && ::Rails.application

            if zeitwerk_available?
              eager_load_via_zeitwerk!
            else
              eager_load_via_application!
            end

            eager_load_engine_models!
          end

          def eager_load_via_zeitwerk!
            loader = ::Rails.autoloaders.main
            models_path = ::Rails.root&.join("app", "models")&.to_s

            if models_path && File.directory?(models_path) && loader.respond_to?(:eager_load_dir)
              loader.eager_load_dir(models_path)
            else
              loader.eager_load
            end
          rescue StandardError => e
            warn "[rails-schema] Zeitwerk eager_load failed (#{e.class}: #{e.message}), " \
                 "trying Rails.application.eager_load!"
            eager_load_via_application!
          end

          def eager_load_via_application!
            ::Rails.application.eager_load!
          rescue StandardError => e
            warn "[rails-schema] eager_load! failed (#{e.class}: #{e.message}), " \
                 "falling back to per-file model loading"
            eager_load_model_files!
          end

          def eager_load_model_files!
            return unless defined?(::Rails.root) && ::Rails.root

            models_path = ::Rails.root.join("app", "models")
            return unless models_path.exist?

            Dir.glob(models_path.join("**/*.rb")).sort.each do |file|
              require file
            rescue StandardError => e
              warn "[rails-schema] Could not load #{file}: #{e.class}: #{e.message}"
            end
          end

          def eager_load_engine_models!
            return unless defined?(::Rails::Engine)

            ::Rails::Engine.subclasses.each do |engine_class|
              next if engine_class <= ::Rails::Application

              engine = engine_class.instance
              next unless engine

              eager_load_engine(engine)
            rescue StandardError => e
              warn "[rails-schema] Could not eager-load engine #{engine_class}: #{e.class}: #{e.message}"
            end
          end

          def eager_load_engine(engine)
            models_paths = engine.paths["app/models"]&.existent || []
            return if models_paths.empty?

            if zeitwerk_available?
              eager_load_engine_zeitwerk(models_paths)
            else
              eager_load_engine_files(models_paths)
            end
          end

          def zeitwerk_available?
            defined?(::Rails.autoloaders) && ::Rails.autoloaders.respond_to?(:main)
          end

          def eager_load_engine_zeitwerk(paths)
            loader = ::Rails.autoloaders.main
            paths.each { |path| loader.eager_load_dir(path) if loader.respond_to?(:eager_load_dir) }
          end

          def eager_load_engine_files(paths)
            paths.each do |path|
              Dir.glob(File.join(path, "**/*.rb")).sort.each do |file|
                require file
              rescue StandardError => e
                warn "[rails-schema] Could not load engine model #{file}: #{e.class}: #{e.message}"
              end
            end
          end

          def excluded?(model)
            @configuration.exclude_models.any? do |pattern|
              if pattern.end_with?("*")
                model.name.start_with?(pattern.delete_suffix("*"))
              else
                model.name == pattern
              end
            end
          end
        end
      end
    end
  end
end
