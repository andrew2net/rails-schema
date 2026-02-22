# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::ColumnReader do
  describe "#read" do
    context "without schema_data" do
      subject(:reader) { described_class.new }

      it "returns columns for a model" do
        columns = reader.read(User)

        expect(columns).to be_an(Array)
        expect(columns.length).to be > 0
      end

      it "includes column attributes" do
        columns = reader.read(User)
        id_col = columns.find { |c| c[:name] == "id" }

        expect(id_col).to include(
          name: "id",
          primary: true
        )
      end

      it "reads nullable attribute" do
        columns = reader.read(User)
        name_col = columns.find { |c| c[:name] == "name" }

        expect(name_col[:nullable]).to eq(false)
      end

      it "detects primary key" do
        columns = reader.read(User)
        primary_cols = columns.select { |c| c[:primary] }

        expect(primary_cols.length).to eq(1)
        expect(primary_cols.first[:name]).to eq("id")
      end
    end

    context "when model.columns raises" do
      subject(:reader) { described_class.new }

      it "warns and returns empty array" do
        model = double("Model", name: "Broken", table_name: "brokens")
        allow(model).to receive(:columns).and_raise(StandardError, "no db")

        columns = nil
        expect {
          columns = reader.read(model)
        }.to output(/Could not read columns for Broken/).to_stderr

        expect(columns).to eq([])
      end
    end

    context "with schema_data" do
      let(:schema_data) do
        {
          "users" => [
            { name: "id", type: "integer", nullable: false, default: nil, primary: true },
            { name: "name", type: "string", nullable: false, default: nil, primary: false },
            { name: "email", type: "string", nullable: false, default: nil, primary: false }
          ]
        }
      end

      subject(:reader) { described_class.new(schema_data: schema_data) }

      it "returns columns from schema_data" do
        columns = reader.read(User)

        expect(columns.length).to eq(3)
        expect(columns.map { |c| c[:name] }).to eq(%w[id name email])
      end

      it "does not hit the database" do
        mock_model = double("Model", table_name: "users")
        allow(mock_model).to receive(:columns).and_raise("should not be called")

        columns = reader.read(mock_model)
        expect(columns.length).to eq(3)
      end

      it "falls back to model columns for unknown tables" do
        columns = reader.read(Post)

        expect(columns).to be_an(Array)
        expect(columns.length).to be > 0
        expect(columns.find { |c| c[:name] == "title" }).to be_truthy
      end
    end
  end
end
