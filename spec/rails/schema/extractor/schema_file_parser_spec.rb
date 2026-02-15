# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::SchemaFileParser do
  describe "#parse_content" do
    subject(:parser) { described_class.new }

    it "parses table names" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name"
        end
      RUBY

      result = parser.parse_content(content)
      expect(result.keys).to eq(["users"])
    end

    it "parses multiple tables" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name"
        end

        create_table "posts" do |t|
          t.string "title"
        end
      RUBY

      result = parser.parse_content(content)
      expect(result.keys).to contain_exactly("users", "posts")
    end

    it "adds implicit integer primary key" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name"
        end
      RUBY

      result = parser.parse_content(content)
      id_col = result["users"].first

      expect(id_col).to eq(name: "id", type: "integer", nullable: false, default: nil, primary: true)
    end

    it "handles id: :uuid primary key" do
      content = <<~RUBY
        create_table "users", id: :uuid do |t|
          t.string "name"
        end
      RUBY

      result = parser.parse_content(content)
      id_col = result["users"].first

      expect(id_col).to eq(name: "id", type: "uuid", nullable: false, default: nil, primary: true)
    end

    it "handles id: :bigint primary key" do
      content = <<~RUBY
        create_table "users", id: :bigint do |t|
          t.string "name"
        end
      RUBY

      result = parser.parse_content(content)
      id_col = result["users"].first

      expect(id_col[:type]).to eq("bigint")
    end

    it "omits primary key when id: false" do
      content = <<~RUBY
        create_table "posts_tags", id: false do |t|
          t.bigint "post_id"
          t.bigint "tag_id"
        end
      RUBY

      result = parser.parse_content(content)
      columns = result["posts_tags"]

      expect(columns.none? { |c| c[:primary] }).to be true
      expect(columns.length).to eq(2)
    end

    it "parses column types and names" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name"
          t.text "bio"
          t.integer "age"
          t.boolean "active"
          t.datetime "created_at"
        end
      RUBY

      result = parser.parse_content(content)
      cols = result["users"].reject { |c| c[:primary] }

      expect(cols.map { |c| [c[:name], c[:type]] }).to eq(
        [%w[name string], %w[bio text], %w[age integer], %w[active boolean], %w[created_at datetime]]
      )
    end

    it "parses null: false" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name", null: false
          t.string "bio"
        end
      RUBY

      result = parser.parse_content(content)
      cols = result["users"].reject { |c| c[:primary] }

      expect(cols.find { |c| c[:name] == "name" }[:nullable]).to be false
      expect(cols.find { |c| c[:name] == "bio" }[:nullable]).to be true
    end

    it "parses string defaults" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "role", default: "member"
        end
      RUBY

      result = parser.parse_content(content)
      col = result["users"].find { |c| c[:name] == "role" }

      expect(col[:default]).to eq("member")
    end

    it "parses numeric defaults" do
      content = <<~RUBY
        create_table "products" do |t|
          t.integer "quantity", default: 0
        end
      RUBY

      result = parser.parse_content(content)
      col = result["products"].find { |c| c[:name] == "quantity" }

      expect(col[:default]).to eq("0")
    end

    it "parses boolean defaults" do
      content = <<~RUBY
        create_table "users" do |t|
          t.boolean "active", default: true
          t.boolean "admin", default: false
        end
      RUBY

      result = parser.parse_content(content)
      active = result["users"].find { |c| c[:name] == "active" }
      admin = result["users"].find { |c| c[:name] == "admin" }

      expect(active[:default]).to eq("true")
      expect(admin[:default]).to eq("false")
    end

    it "returns nil default when none specified" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "name"
        end
      RUBY

      result = parser.parse_content(content)
      col = result["users"].find { |c| c[:name] == "name" }

      expect(col[:default]).to be_nil
    end

    it "skips t.index lines" do
      content = <<~RUBY
        create_table "users" do |t|
          t.string "email"
          t.index ["email"], name: "index_users_on_email", unique: true
        end
      RUBY

      result = parser.parse_content(content)
      cols = result["users"].reject { |c| c[:primary] }

      expect(cols.length).to eq(1)
      expect(cols.first[:name]).to eq("email")
    end

    it "returns empty hash for empty content" do
      expect(parser.parse_content("")).to eq({})
    end
  end

  describe "#parse" do
    it "returns empty hash when file does not exist" do
      parser = described_class.new("/nonexistent/path/schema.rb")
      expect(parser.parse).to eq({})
    end

    it "parses a schema file from path" do
      require "tempfile"
      file = Tempfile.new(["schema", ".rb"])
      file.write(<<~RUBY)
        create_table "users" do |t|
          t.string "name"
        end
      RUBY
      file.close

      parser = described_class.new(file.path)
      result = parser.parse

      expect(result.keys).to eq(["users"])
    ensure
      file&.unlink
    end
  end
end
