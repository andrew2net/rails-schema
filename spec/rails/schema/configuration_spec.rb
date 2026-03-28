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

  it "has default exclude_model_if" do
    expect(config.exclude_model_if).to be_nil
  end

  it "has default model_schema_group" do
    expect(config.model_schema_group).to be_nil
  end

  it "has default show_through_edges" do
    expect(config.show_through_edges).to eq(true)
  end

  describe "#resolved_group_proc" do
    it "returns nil when model_schema_group is nil" do
      expect(config.resolved_group_proc).to be_nil
    end

    it "returns a proc that splits namespaces for :namespaces" do
      config.model_schema_group = :namespaces
      proc = config.resolved_group_proc
      model = double(name: "Admin::Reports::Summary")

      expect(proc.call(model)).to eq(%w[Admin Reports])
    end

    it "returns empty array for non-namespaced model with :namespaces" do
      config.model_schema_group = :namespaces
      proc = config.resolved_group_proc
      model = double(name: "User")

      expect(proc.call(model)).to eq([])
    end

    it "passes through a custom Proc" do
      custom_proc = ->(model) { [model.name.downcase] }
      config.model_schema_group = custom_proc

      expect(config.resolved_group_proc).to eq(custom_proc)
    end

    it "raises ArgumentError for invalid values" do
      config.model_schema_group = "invalid"

      expect { config.resolved_group_proc }.to raise_error(ArgumentError)
    end
  end

  it "allows setting attributes" do
    config.output_path = "custom/path.html"
    config.exclude_models = ["User"]
    config.exclude_model_if = ->(model) { model.name == "Post" }
    config.title = "My Schema"
    config.theme = :dark
    config.expand_columns = true
    config.schema_format = :sql

    expect(config.output_path).to eq("custom/path.html")
    expect(config.exclude_models).to eq(["User"])
    expect(config.exclude_model_if).to be_a(Proc)
    expect(config.title).to eq("My Schema")
    expect(config.theme).to eq(:dark)
    expect(config.expand_columns).to eq(true)
    expect(config.schema_format).to eq(:sql)
  end
end
