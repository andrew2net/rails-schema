# frozen_string_literal: true

module Rails
  module Schema
    module Extractor
      class SchemaFileParser
        def initialize(schema_path = nil)
          @schema_path = schema_path
        end

        def parse
          path = resolve_path
          return {} unless path && File.exist?(path)

          parse_content(File.read(path))
        end

        def parse_content(content)
          @tables = {}
          @current_table = nil
          @pk_type = nil
          @has_pk = true

          content.each_line { |line| process_line(line.strip) }

          @tables
        end

        private

        def resolve_path
          return @schema_path if @schema_path

          if defined?(::Rails.root) && ::Rails.root
            ::Rails.root.join("db", "schema.rb").to_s
          else
            File.join(Dir.pwd, "db", "schema.rb")
          end
        end

        def extract_pk_type(line)
          if (match = line.match(/id:\s*:(\w+)/))
            match[1]
          else
            "integer"
          end
        end

        def parse_column(line)
          return nil if line.start_with?("t.index")

          match = line.match(/\At\.(\w+)\s+"(\w+)"(.*)/)
          return nil unless match

          type = match[1]
          name = match[2]
          options = match[3]

          {
            name: name,
            type: type,
            nullable: !options.match?(/null:\s*false/),
            default: extract_default(options),
            primary: false
          }
        end

        def process_line(stripped)
          if (match = stripped.match(/\Acreate_table\s+"(\w+)"/))
            start_table(match, stripped)
          elsif @current_table && stripped == "end"
            close_table
          elsif @current_table && (col = parse_column(stripped))
            @tables[@current_table] << col
          end
        end

        def start_table(match, stripped)
          @current_table = match[1]
          @tables[@current_table] = []
          @has_pk = !stripped.match?(/id:\s*false/)
          @pk_type = extract_pk_type(stripped)
        end

        def close_table
          if @has_pk
            pk_column = { name: "id", type: @pk_type, nullable: false, default: nil, primary: true }
            @tables[@current_table].unshift(pk_column)
          end
          @current_table = nil
          @pk_type = nil
          @has_pk = true
        end

        def extract_default(options)
          if (match = options.match(/default:\s*(?:"([^"]*)"|(\d+(?:\.\d+)?))/))
            match[1] || match[2]
          elsif options.match?(/default:\s*true/)
            "true"
          elsif options.match?(/default:\s*false/)
            "false"
          end
        end
      end
    end
  end
end
