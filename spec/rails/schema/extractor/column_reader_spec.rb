# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::ColumnReader do
  subject(:reader) { described_class.new }

  describe "#read" do
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
end
