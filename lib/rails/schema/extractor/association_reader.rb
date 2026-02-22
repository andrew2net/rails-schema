# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class AssociationReader
        def read(model)
          model.reflect_on_all_associations.filter_map do |ref|
            next if skip_association?(ref)

            build_association_data(model, ref)
          end
        end

        private

        def skip_association?(ref)
          # Skip polymorphic belongs_to — no fixed target model
          ref.macro == :belongs_to && ref.options[:polymorphic]
        end

        def build_association_data(model, ref)
          {
            from: model.name,
            to: target_model_name(ref),
            association_type: ref.macro.to_s,
            label: ref.name.to_s,
            foreign_key: ref.foreign_key.to_s,
            through: through_name(ref),
            polymorphic: polymorphic?(ref)
          }
        rescue StandardError => e
          warn "[rails-schema] Could not read association #{ref.name} on #{model.name}: #{e.class}: #{e.message}"
          nil
        end

        def through_name(ref)
          ref.options[:through]&.to_s
        end

        def polymorphic?(ref)
          ref.options[:as] ? true : false
        end

        def target_model_name(ref)
          ref.klass.name
        rescue StandardError => e
          warn "[rails-schema] Could not resolve target for #{ref.name}, " \
               "falling back to #{ref.class_name}: #{e.class}: #{e.message}"
          ref.class_name
        end
      end
    end
  end
end
