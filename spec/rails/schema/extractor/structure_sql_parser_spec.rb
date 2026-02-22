# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::StructureSqlParser do
  describe "#parse_content" do
    subject(:parser) { described_class.new }

    it "parses table names" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "name" character varying
        );
      SQL

      result = parser.parse_content(content)
      expect(result.keys).to eq(["users"])
    end

    it "parses multiple tables" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "name" character varying
        );

        CREATE TABLE "posts" (
          "id" bigint NOT NULL,
          "title" character varying
        );
      SQL

      result = parser.parse_content(content)
      expect(result.keys).to contain_exactly("users", "posts")
    end

    it "parses column names and maps SQL types to Rails types" do
      content = <<~SQL
        CREATE TABLE "users" (
          "name" character varying,
          "bio" text,
          "age" integer,
          "active" boolean,
          "created_at" timestamp without time zone NOT NULL
        );
      SQL

      result = parser.parse_content(content)
      cols = result["users"]

      expect(cols.map { |c| [c[:name], c[:type]] }).to eq(
        [%w[name string], %w[bio text], %w[age integer], %w[active boolean], %w[created_at datetime]]
      )
    end

    it "maps bigint type" do
      content = <<~SQL
        CREATE TABLE "posts" (
          "user_id" bigint
        );
      SQL

      result = parser.parse_content(content)
      col = result["posts"].find { |c| c[:name] == "user_id" }

      expect(col[:type]).to eq("bigint")
    end

    it "maps json and jsonb types" do
      content = <<~SQL
        CREATE TABLE "events" (
          "data" json,
          "metadata" jsonb
        );
      SQL

      result = parser.parse_content(content)
      cols = result["events"]

      expect(cols.find { |c| c[:name] == "data" }[:type]).to eq("json")
      expect(cols.find { |c| c[:name] == "metadata" }[:type]).to eq("jsonb")
    end

    it "maps uuid type" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" uuid NOT NULL
        );
      SQL

      result = parser.parse_content(content)
      col = result["users"].first

      expect(col[:type]).to eq("uuid")
    end

    it "maps numeric and decimal types" do
      content = <<~SQL
        CREATE TABLE "products" (
          "price" numeric,
          "weight" decimal
        );
      SQL

      result = parser.parse_content(content)

      expect(result["products"].find { |c| c[:name] == "price" }[:type]).to eq("decimal")
      expect(result["products"].find { |c| c[:name] == "weight" }[:type]).to eq("decimal")
    end

    it "maps date type" do
      content = <<~SQL
        CREATE TABLE "events" (
          "event_date" date
        );
      SQL

      result = parser.parse_content(content)

      expect(result["events"].first[:type]).to eq("date")
    end

    it "maps float and double precision types" do
      content = <<~SQL
        CREATE TABLE "measurements" (
          "value" float,
          "precise_value" double precision
        );
      SQL

      result = parser.parse_content(content)

      expect(result["measurements"].find { |c| c[:name] == "value" }[:type]).to eq("float")
      expect(result["measurements"].find { |c| c[:name] == "precise_value" }[:type]).to eq("float")
    end

    it "detects NOT NULL as nullable: false" do
      content = <<~SQL
        CREATE TABLE "users" (
          "name" character varying NOT NULL,
          "bio" text
        );
      SQL

      result = parser.parse_content(content)
      cols = result["users"]

      expect(cols.find { |c| c[:name] == "name" }[:nullable]).to be false
      expect(cols.find { |c| c[:name] == "bio" }[:nullable]).to be true
    end

    it "parses string defaults" do
      content = <<~SQL
        CREATE TABLE "users" (
          "role" character varying DEFAULT 'member'::character varying
        );
      SQL

      result = parser.parse_content(content)
      col = result["users"].find { |c| c[:name] == "role" }

      expect(col[:default]).to eq("member")
    end

    it "parses numeric defaults" do
      content = <<~SQL
        CREATE TABLE "products" (
          "quantity" integer DEFAULT 0
        );
      SQL

      result = parser.parse_content(content)
      col = result["products"].find { |c| c[:name] == "quantity" }

      expect(col[:default]).to eq("0")
    end

    it "parses boolean defaults" do
      content = <<~SQL
        CREATE TABLE "users" (
          "active" boolean DEFAULT true,
          "admin" boolean DEFAULT false
        );
      SQL

      result = parser.parse_content(content)
      active = result["users"].find { |c| c[:name] == "active" }
      admin = result["users"].find { |c| c[:name] == "admin" }

      expect(active[:default]).to eq("true")
      expect(admin[:default]).to eq("false")
    end

    it "returns nil default when none specified" do
      content = <<~SQL
        CREATE TABLE "users" (
          "name" character varying
        );
      SQL

      result = parser.parse_content(content)
      col = result["users"].find { |c| c[:name] == "name" }

      expect(col[:default]).to be_nil
    end

    it "detects primary key from PRIMARY KEY constraint" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "name" character varying,
          CONSTRAINT "users_pkey" PRIMARY KEY ("id")
        );
      SQL

      result = parser.parse_content(content)
      id_col = result["users"].find { |c| c[:name] == "id" }

      expect(id_col[:primary]).to be true
      expect(result["users"].find { |c| c[:name] == "name" }[:primary]).to be false
    end

    it "detects primary key from inline PRIMARY KEY" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint PRIMARY KEY,
          "name" character varying
        );
      SQL

      result = parser.parse_content(content)
      id_col = result["users"].find { |c| c[:name] == "id" }

      expect(id_col[:primary]).to be true
    end

    it "handles tables without a primary key" do
      content = <<~SQL
        CREATE TABLE "posts_tags" (
          "post_id" bigint,
          "tag_id" bigint
        );
      SQL

      result = parser.parse_content(content)
      columns = result["posts_tags"]

      expect(columns.none? { |c| c[:primary] }).to be true
      expect(columns.length).to eq(2)
    end

    it "handles unquoted identifiers" do
      content = <<~SQL
        CREATE TABLE users (
          id bigint NOT NULL,
          name character varying
        );
      SQL

      result = parser.parse_content(content)
      expect(result.keys).to eq(["users"])
      expect(result["users"].map { |c| c[:name] }).to eq(%w[id name])
    end

    it "skips CONSTRAINT lines" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "email" character varying,
          CONSTRAINT "users_pkey" PRIMARY KEY ("id"),
          CONSTRAINT "users_email_check" CHECK ((length(("email")::text) > 0))
        );
      SQL

      result = parser.parse_content(content)
      cols = result["users"]

      expect(cols.length).to eq(2)
      expect(cols.map { |c| c[:name] }).to eq(%w[id email])
    end

    it "skips UNIQUE constraint lines" do
      content = <<~SQL
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "email" character varying,
          UNIQUE ("email")
        );
      SQL

      result = parser.parse_content(content)

      expect(result["users"].length).to eq(2)
    end

    it "skips FOREIGN KEY constraint lines" do
      content = <<~SQL
        CREATE TABLE "posts" (
          "id" bigint NOT NULL,
          "user_id" bigint,
          FOREIGN KEY ("user_id") REFERENCES "users" ("id")
        );
      SQL

      result = parser.parse_content(content)

      expect(result["posts"].length).to eq(2)
    end

    it "handles schema-qualified table names" do
      content = <<~SQL
        CREATE TABLE public.users (
          id bigint NOT NULL,
          name character varying
        );

        CREATE TABLE public.posts (
          id bigint NOT NULL,
          title text
        );
      SQL

      result = parser.parse_content(content)
      expect(result.keys).to contain_exactly("users", "posts")
    end

    it "parses timestamp with precision" do
      content = <<~SQL
        CREATE TABLE "events" (
          "created_at" timestamp(6) without time zone NOT NULL,
          "updated_at" timestamp(6) with time zone
        );
      SQL

      result = parser.parse_content(content)
      cols = result["events"]

      expect(cols.map { |c| c[:type] }).to eq(%w[datetime datetime])
      expect(cols.first[:nullable]).to be false
    end

    it "returns empty hash for empty content" do
      expect(parser.parse_content("")).to eq({})
    end
  end

  describe "#parse" do
    it "returns empty hash when file does not exist" do
      parser = described_class.new("/nonexistent/path/structure.sql")
      expect(parser.parse).to eq({})
    end

    it "parses a structure.sql file from path" do
      require "tempfile"
      file = Tempfile.new(["structure", ".sql"])
      file.write(<<~SQL)
        CREATE TABLE "users" (
          "id" bigint NOT NULL,
          "name" character varying,
          CONSTRAINT "users_pkey" PRIMARY KEY ("id")
        );
      SQL
      file.close

      parser = described_class.new(file.path)
      result = parser.parse

      expect(result.keys).to eq(["users"])
      expect(result["users"].find { |c| c[:name] == "id" }[:primary]).to be true
    ensure
      file&.unlink
    end
  end
end
