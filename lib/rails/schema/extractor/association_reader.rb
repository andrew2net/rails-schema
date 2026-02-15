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
            through: ref.options[:through]&.to_s,
            polymorphic: ref.options[:as] ? true : false
          }
        rescue StandardError
          nil
        end

        def target_model_name(ref)
          ref.klass.name
        rescue StandardError
          ref.class_name
        end
      end
    end
  end
end
