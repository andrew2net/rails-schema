# frozen_string_literal: true

module Rails
  module Schema
    class Railtie < ::Rails::Railtie
      rake_tasks do
        namespace :rails_schema do
          desc "Generate an interactive HTML schema diagram"
          task generate: :environment do
            path = ::Rails::Schema.generate
            puts "Schema diagram generated: #{path}"
          end
        end
      end
    end
  end
end
