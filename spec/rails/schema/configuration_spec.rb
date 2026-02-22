# frozen_string_literal: true

RSpec.describe Rails::Schema::Configuration do
  subject(:config) { described_class.new }

  it "has default output_path" do
    expect(config.output_path).to eq("docs/schema.html")
  end

  it "has default exclude_models" do
    expect(config.exclude_models).to eq([])
  end

  it "has default title" do
    expect(config.title).to eq("Database Schema")
  end

  it "has default theme" do
    expect(config.theme).to eq(:auto)
  end

  it "has default expand_columns" do
    expect(config.expand_columns).to eq(false)
  end

  it "has default schema_format" do
    expect(config.schema_format).to eq(:auto)
  end

  it "allows setting attributes" do
    config.output_path = "custom/path.html"
    config.exclude_models = ["User"]
    config.title = "My Schema"
    config.theme = :dark
    config.expand_columns = true
    config.schema_format = :sql

    expect(config.output_path).to eq("custom/path.html")
    expect(config.exclude_models).to eq(["User"])
    expect(config.title).to eq("My Schema")
    expect(config.theme).to eq(:dark)
    expect(config.expand_columns).to eq(true)
    expect(config.schema_format).to eq(:sql)
  end
end
