# frozen_string_literal: true

require "set"

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
                               timestamp(?:\(\d+\))?\s+with(?:out)?\s+time\s+zone)/ix.freeze
        CONSTRAINT_RE = /\A(CONSTRAINT|UNIQUE|CHECK|EXCLUDE|FOREIGN\s+KEY)\b/i.freeze
        PK_CONSTRAINT_RE = /PRIMARY\s+KEY\s*\(([^)]+)\)/i.freeze

        # Set of table names that are backed by SQL views (CREATE VIEW), not
        # real tables. Populated by #parse / #parse_content. Lets downstream
        # code badge view-backed models on the diagram.
        attr_reader :views

        def initialize(structure_path = nil)
          @structure_path = structure_path
          @views = Set.new
        end

        def parse
          path = resolve_path
          return {} unless path && File.exist?(path)

          parse_content(File.read(path))
        end

        def parse_content(content)
          tables = {}
          @views = Set.new

          content.scan(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w."]+)\s*\((.*?)\)\s*;/mi) do |table_name, body|
            name = extract_table_name(table_name)
            columns, pk_columns = parse_table_body(body)
            pk_columns.each { |pk| columns.find { |c| c[:name] == pk }&.[]= :primary, true }
            tables[name] = columns
          end

          parse_views(content, tables)
          tables
        end

        private

        # Views carry no column-type information in their DDL, so offline we can
        # only recover column names (from the SQLite hint comment or the SELECT
        # list). ColumnReader prefers live DB introspection for views when a
        # connection is available; these names are the offline fallback.
        def parse_views(content, tables)
          content.scan(/CREATE\s+VIEW\s+([\w."]+)\s+AS\b(.*?);/mi) do |raw_name, body|
            name = extract_table_name(raw_name)
            @views << name
            tables[name] = view_columns(name, body)
          end
        end

        def view_columns(name, body)
          view_column_names(name, body).map do |col_name|
            { name: col_name, type: "", nullable: true, default: nil, primary: false }
          end
        end

        def view_column_names(name, body)
          if (match = body.match(%r{/\*\s*#{Regexp.escape(name)}\s*\(([^)]*)\)\s*\*/}))
            match[1].split(",").map { |c| unquote(c.strip) }
          else
            select_list_aliases(body)
          end
        end

        def select_list_aliases(body)
          match = body.match(/\bSELECT\b(.*?)\bFROM\b/mi)
          return [] unless match

          split_columns(match[1]).filter_map { |item| column_alias(item) }
        end

        def column_alias(item)
          item = strip_comments(item).strip
          return nil if item.empty? || item.include?("*")

          item[/\bAS\s+"?(\w+)"?\s*\z/i, 1] || item[/"?(\w+)"?\s*\z/, 1]
        end

        def resolve_path
          return @structure_path if @structure_path
          return ::Rails.root.join("db", "structure.sql").to_s if defined?(::Rails.root) && ::Rails.root

          File.join(Dir.pwd, "db", "structure.sql")
        end

        def unquote(identifier)
          identifier.delete('"')
        end

        def extract_table_name(raw)
          unquote(raw).split(".").last
        end

        def parse_table_body(body)
          columns = []
          pk_columns = []
          split_columns(body).each do |segment|
            line = segment.strip
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

        # Splits a table body on top-level commas, ignoring commas inside
        # parentheses (e.g. decimal(5,4), FK clauses) or quoted strings. This
        # handles both PostgreSQL (one column per line) and SQLite (whole table
        # on a single line) structure.sql dumps.
        def split_columns(body)
          segments = []
          current = +""
          state = { depth: 0, squote: false, dquote: false }
          strip_comments(body).each_char do |ch|
            if split_point?(ch, state)
              segments << current
              current = +""
            else
              current << ch
            end
          end
          segments << current
        end

        def split_point?(char, state)
          toggle_quote(char, state)
          return false if quoted?(state)

          case char
          when "(" then state[:depth] += 1
          when ")" then state[:depth] -= 1
          when "," then return state[:depth].zero?
          end
          false
        end

        def toggle_quote(char, state)
          state[:squote] = !state[:squote] if char == "'" && !state[:dquote]
          state[:dquote] = !state[:dquote] if char == '"' && !state[:squote]
        end

        def quoted?(state)
          state[:squote] || state[:dquote]
        end

        def strip_comments(sql)
          sql.gsub(%r{/\*.*?\*/}m, "")
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
