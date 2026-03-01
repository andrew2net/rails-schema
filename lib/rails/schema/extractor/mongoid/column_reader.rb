# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      module Mongoid
        class ColumnReader
          TYPE_MAP = {
            "String" => "string",
            "Integer" => "integer",
            "Float" => "float",
            "BigDecimal" => "decimal",
            "Date" => "date",
            "Time" => "datetime",
            "DateTime" => "datetime",
            "Array" => "array",
            "Hash" => "hash",
            "Regexp" => "regexp",
            "Symbol" => "symbol",
            "Range" => "range",
            "BSON::ObjectId" => "object_id",
            "Mongoid::Boolean" => "boolean",
            "TrueClass" => "boolean",
            "FalseClass" => "boolean"
          }.freeze

          def read(model)
            model.fields.map do |name, field|
              {
                name: name,
                type: map_type(field.type),
                nullable: !required_field?(model, name),
                primary: name == "_id",
                default: format_default(field.default_val)
              }
            end
          rescue StandardError => e
            warn "[rails-schema] Could not read Mongoid fields for #{model.name}: #{e.class}: #{e.message}"
            []
          end

          private

          def required_field?(model, field_name)
            return true if field_name == "_id"
            return false unless model.respond_to?(:validators_on)

            model.validators_on(field_name).any? do |v|
              v.class.name.include?("PresenceValidator")
            end
          end

          def map_type(type)
            return "object" if type.nil?

            TYPE_MAP.fetch(type.name, type.name.downcase)
          end

          def format_default(default)
            case default
            when Proc
              "(dynamic)"
            else
              default
            end
          end
        end
      end
    end
  end
end
