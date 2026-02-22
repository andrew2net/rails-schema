# frozen_string_literal: true

RSpec.describe Rails::Schema do
  it "has a version number" do
    expect(Rails::Schema::VERSION).not_to be_nil
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(Rails::Schema.configuration).to be_a(Rails::Schema::Configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      Rails::Schema.configure do |config|
        config.title = "My Custom Title"
      end

      expect(Rails::Schema.configuration.title).to eq("My Custom Title")
    end
  end

  describe ".reset_configuration!" do
    it "resets to defaults" do
      Rails::Schema.configure { |c| c.title = "Changed" }
      Rails::Schema.reset_configuration!

      expect(Rails::Schema.configuration.title).to eq("Database Schema")
    end
  end

  describe ".configure" do
    it "allows setting schema_format" do
      Rails::Schema.configure do |config|
        config.schema_format = :sql
      end

      expect(Rails::Schema.configuration.schema_format).to eq(:sql)
    ensure
      Rails::Schema.reset_configuration!
    end
  end

  describe ".generate" do
    let(:schema_data) { { "users" => [{ name: "id", type: "integer" }] } }
    let(:models) { [double("User", name: "User")] }
    let(:graph_data) { { nodes: [], edges: [], metadata: {} } }
    let(:output_path) { "/tmp/schema.html" }

    let(:ruby_parser) { instance_double(Rails::Schema::Extractor::SchemaFileParser, parse: schema_data) }
    let(:scanner) { instance_double(Rails::Schema::Extractor::ModelScanner, scan: models) }
    let(:column_reader) { instance_double(Rails::Schema::Extractor::ColumnReader) }
    let(:graph_builder) { instance_double(Rails::Schema::Transformer::GraphBuilder, build: graph_data) }
    let(:html_generator) { instance_double(Rails::Schema::Renderer::HtmlGenerator, render_to_file: output_path) }

    before do
      allow(Rails::Schema::Extractor::SchemaFileParser).to receive(:new).and_return(ruby_parser)
      allow(Rails::Schema::Extractor::ModelScanner).to receive(:new).and_return(scanner)
      allow(Rails::Schema::Extractor::ColumnReader).to receive(:new).and_return(column_reader)
      allow(Rails::Schema::Transformer::GraphBuilder).to receive(:new).and_return(graph_builder)
      allow(Rails::Schema::Renderer::HtmlGenerator).to receive(:new).and_return(html_generator)
    end

    it "calls the pipeline and returns the output path" do
      result = Rails::Schema.generate

      expect(scanner).to have_received(:scan)
      expect(graph_builder).to have_received(:build).with(models)
      expect(html_generator).to have_received(:render_to_file).with(nil)
      expect(result).to eq(output_path)
    end

    it "passes output: to render_to_file" do
      Rails::Schema.generate(output: "/tmp/custom.html")

      expect(html_generator).to have_received(:render_to_file).with("/tmp/custom.html")
    end

    it "passes schema_data through the pipeline" do
      Rails::Schema.generate

      expect(Rails::Schema::Extractor::ModelScanner).to have_received(:new).with(schema_data: schema_data)
      expect(Rails::Schema::Extractor::ColumnReader).to have_received(:new).with(schema_data: schema_data)
    end
  end

  describe "parse_schema (via .generate)" do
    let(:ruby_data) { { "users" => [{ name: "id", type: "integer" }] } }
    let(:sql_data) { { "posts" => [{ name: "id", type: "bigint" }] } }

    let(:ruby_parser) { instance_double(Rails::Schema::Extractor::SchemaFileParser, parse: ruby_data) }
    let(:sql_parser) { instance_double(Rails::Schema::Extractor::StructureSqlParser, parse: sql_data) }

    let(:scanner) { instance_double(Rails::Schema::Extractor::ModelScanner, scan: []) }
    let(:column_reader) { instance_double(Rails::Schema::Extractor::ColumnReader) }
    let(:graph_builder) { instance_double(Rails::Schema::Transformer::GraphBuilder, build: { nodes: [], edges: [], metadata: {} }) }
    let(:html_generator) { instance_double(Rails::Schema::Renderer::HtmlGenerator, render_to_file: "/tmp/out.html") }

    before do
      allow(Rails::Schema::Extractor::SchemaFileParser).to receive(:new).and_return(ruby_parser)
      allow(Rails::Schema::Extractor::StructureSqlParser).to receive(:new).and_return(sql_parser)
      allow(Rails::Schema::Extractor::ModelScanner).to receive(:new).and_return(scanner)
      allow(Rails::Schema::Extractor::ColumnReader).to receive(:new).and_return(column_reader)
      allow(Rails::Schema::Transformer::GraphBuilder).to receive(:new).and_return(graph_builder)
      allow(Rails::Schema::Renderer::HtmlGenerator).to receive(:new).and_return(html_generator)
    end

    context "when schema_format is :ruby" do
      before { Rails::Schema.configure { |c| c.schema_format = :ruby } }

      it "calls SchemaFileParser and not StructureSqlParser" do
        Rails::Schema.generate

        expect(ruby_parser).to have_received(:parse)
        expect(sql_parser).not_to have_received(:parse)
      end
    end

    context "when schema_format is :sql" do
      before { Rails::Schema.configure { |c| c.schema_format = :sql } }

      it "calls StructureSqlParser and not SchemaFileParser" do
        Rails::Schema.generate

        expect(sql_parser).to have_received(:parse)
        expect(ruby_parser).not_to have_received(:parse)
      end
    end

    context "when schema_format is :auto and ruby file returns data" do
      before { Rails::Schema.configure { |c| c.schema_format = :auto } }

      it "uses SchemaFileParser data without falling back to StructureSqlParser" do
        Rails::Schema.generate

        expect(ruby_parser).to have_received(:parse)
        expect(sql_parser).not_to have_received(:parse)
        expect(Rails::Schema::Extractor::ModelScanner).to have_received(:new).with(schema_data: ruby_data)
      end
    end

    context "when schema_format is :auto and ruby file returns empty hash" do
      let(:ruby_parser) { instance_double(Rails::Schema::Extractor::SchemaFileParser, parse: {}) }

      before { Rails::Schema.configure { |c| c.schema_format = :auto } }

      it "falls back to StructureSqlParser" do
        Rails::Schema.generate

        expect(ruby_parser).to have_received(:parse)
        expect(sql_parser).to have_received(:parse)
        expect(Rails::Schema::Extractor::ModelScanner).to have_received(:new).with(schema_data: sql_data)
      end
    end
  end
end
