# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      module Mongoid
        class AssociationReader
          ASSOCIATION_TYPE_MAP = {
            "Mongoid::Association::Referenced::HasMany" => "has_many",
            "Mongoid::Association::Referenced::HasOne" => "has_one",
            "Mongoid::Association::Referenced::BelongsTo" => "belongs_to",
            "Mongoid::Association::Referenced::HasAndBelongsToMany" => "has_and_belongs_to_many",
            "Mongoid::Association::Embedded::EmbedsMany" => "embeds_many",
            "Mongoid::Association::Embedded::EmbedsOne" => "embeds_one",
            "Mongoid::Association::Embedded::EmbeddedIn" => "embedded_in"
          }.freeze

          def read(model)
            model.relations.filter_map do |name, metadata|
              next if skip_association?(metadata)

              build_association_data(model, name, metadata)
            end
          rescue StandardError => e
            warn "[rails-schema] Could not read Mongoid relations for #{model.name}: #{e.class}: #{e.message}"
            []
          end

          private

          def skip_association?(metadata)
            association_type_string(metadata) == "belongs_to" && metadata.polymorphic?
          end

          def build_association_data(model, name, metadata)
            {
              from: model.name,
              to: metadata.class_name,
              association_type: association_type_string(metadata),
              label: name.to_s,
              foreign_key: metadata.respond_to?(:foreign_key) ? metadata.foreign_key&.to_s : nil,
              through: nil,
              polymorphic: metadata.respond_to?(:as) && metadata.as ? true : false
            }
          rescue StandardError => e
            warn "[rails-schema] Could not read Mongoid association #{name} on #{model.name}: " \
                 "#{e.class}: #{e.message}"
            nil
          end

          def association_type_string(metadata)
            # metadata.class returns the association class (e.g. Mongoid::Association::Referenced::HasMany)
            ASSOCIATION_TYPE_MAP.fetch(metadata.class.name, metadata.class.name)
          end
        end
      end
    end
  end
end
