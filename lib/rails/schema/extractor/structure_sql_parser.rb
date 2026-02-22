# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class StructureSqlParser
        SQL_TYPE_MAP = {
          "character varying" => "string", "varchar" => "string",
          "integer" => "integer", "smallint" => "integer", "serial" => "integer",
          "bigint" => "bigint", "bigserial" => "bigint",
          "boolean" => "boolean", "text" => "text",
          "timestamp without time zone" => "datetime", "timestamp with time zone" => "datetime",
          "timestamp" => "datetime",
          "json" => "json", "jsonb" => "jsonb", "uuid" => "uuid",
          "numeric" => "decimal", "decimal" => "decimal", "money" => "decimal",
          "date" => "date",
          "float" => "float", "double precision" => "float", "real" => "float",
          "bytea" => "binary"
        }.freeze

        COMPOUND_TYPE_RE = /\A(character\s+varying|bit\s+varying|double\s+precision|
                               timestamp(?:\(\d+\))?\s+with(?:out)?\s+time\s+zone)/ix
        CONSTRAINT_RE = /\A(CONSTRAINT|UNIQUE|CHECK|EXCLUDE|FOREIGN\s+KEY)\b/i
        PK_CONSTRAINT_RE = /PRIMARY\s+KEY\s*\(([^)]+)\)/i

        def initialize(structure_path = nil)
          @structure_path = structure_path
        end

        def parse
          path = resolve_path
          return {} unless path && File.exist?(path)

          parse_content(File.read(path))
        end

        def parse_content(content)
          tables = {}

          content.scan(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w."]+)\s*\((.*?)\)\s*;/mi) do |table_name, body|
            name = extract_table_name(table_name)
            columns, pk_columns = parse_table_body(body)
            pk_columns.each { |pk| columns.find { |c| c[:name] == pk }&.[]= :primary, true }
            tables[name] = columns
          end

          tables
        end

        private

        def resolve_path
          return @structure_path if @structure_path
          return ::Rails.root.join("db", "structure.sql").to_s if defined?(::Rails.root) && ::Rails.root

          File.join(Dir.pwd, "db", "structure.sql")
        end

        def unquote(identifier) = identifier.delete('"')

        def extract_table_name(raw)
          unquote(raw).split(".").last
        end

        def parse_table_body(body)
          columns = []
          pk_columns = []
          body.each_line do |raw|
            line = raw.strip.chomp(",")
            next if line.empty?

            if (pk = extract_pk_constraint(line))
              pk_columns.concat(pk)
            elsif !line.match?(CONSTRAINT_RE) && (col = parse_column_line(line))
              pk_columns << col[:name] if col.delete(:inline_pk)
              columns << col
            end
          end
          [columns, pk_columns]
        end

        def extract_pk_constraint(line)
          return unless (match = line.match(PK_CONSTRAINT_RE))

          match[1].split(",").map { |c| unquote(c.strip) }
        end

        def parse_column_line(line)
          match = line.match(/\A("?\w+"?)\s+(.+)/i)
          return nil unless match

          rest = match[2]
          type = extract_type(rest)
          return nil unless type

          build_column(unquote(match[1]), rest, type)
        end

        def build_column(col_name, rest, type)
          {
            name: col_name,
            type: SQL_TYPE_MAP.fetch(type, type),
            nullable: !rest.match?(/\bNOT\s+NULL\b/i),
            default: extract_default(rest),
            primary: false,
            inline_pk: rest.match?(/\bPRIMARY\s+KEY\b/i)
          }
        end

        def extract_type(rest)
          if (m = rest.match(COMPOUND_TYPE_RE))
            m[1].downcase.gsub(/\(\d+\)/, "")
          elsif rest.match?(/\A(FOREIGN\s+KEY)\b/i)
            nil
          else
            rest[/\A(\w+)/i, 1]&.downcase
          end
        end

        def extract_default(rest)
          case rest
          when /\bDEFAULT\s+'([^']*)'(?:::\w+)?/i, /\bDEFAULT\s+(\d+(?:\.\d+)?)\b/i
            Regexp.last_match(1)
          when /\bDEFAULT\s+true\b/i then "true"
          when /\bDEFAULT\s+false\b/i then "false"
          end
        end
      end
    end
  end
end
