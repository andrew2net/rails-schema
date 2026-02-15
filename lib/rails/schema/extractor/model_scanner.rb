# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class ModelScanner
        def initialize(configuration: ::Rails::Schema.configuration)
          @configuration = configuration
        end

        def scan
          eager_load_models!
          ActiveRecord::Base.descendants
                            .reject(&:abstract_class?)
                            .reject { |m| m.name.nil? }
                            .select { |m| safe_table_exists?(m) }
                            .reject { |m| excluded?(m) }
                            .sort_by(&:name)
        end

        private

        def eager_load_models!
          ::Rails.application.eager_load! if defined?(::Rails.application) && ::Rails.application
        rescue StandardError
          nil
        end

        def safe_table_exists?(model)
          model.table_exists?
        rescue StandardError
          false
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
