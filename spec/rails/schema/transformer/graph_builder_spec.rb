# frozen_string_literal: true

RSpec.describe Rails::Schema::Transformer::GraphBuilder do
  subject(:builder) { described_class.new }

  let(:models) { [User, Post, Comment, Tag] }

  describe "#build" do
    let(:result) { builder.build(models) }

    it "returns nodes for all models" do
      node_ids = result[:nodes].map { |n| n[:id] }

      expect(node_ids).to contain_exactly("User", "Post", "Comment", "Tag")
    end

    it "includes table_name in nodes" do
      user_node = result[:nodes].find { |n| n[:id] == "User" }

      expect(user_node[:table_name]).to eq("users")
    end

    it "includes columns in nodes" do
      user_node = result[:nodes].find { |n| n[:id] == "User" }

      expect(user_node[:columns]).to be_an(Array)
      expect(user_node[:columns].map { |c| c[:name] }).to include("id", "name", "email")
    end

    it "creates edges for associations" do
      expect(result[:edges]).to be_an(Array)
      expect(result[:edges].length).to be > 0
    end

    it "only creates edges where both endpoints exist" do
      node_ids = result[:nodes].map { |n| n[:id] }

      result[:edges].each do |edge|
        expect(node_ids).to include(edge[:from])
        expect(node_ids).to include(edge[:to])
      end
    end

    it "includes metadata" do
      expect(result[:metadata]).to include(:generated_at, :model_count)
      expect(result[:metadata][:model_count]).to eq(4)
    end

    it "includes a User -> Post edge" do
      edge = result[:edges].find { |e| e[:from] == "User" && e[:to] == "Post" }

      expect(edge).not_to be_nil
      expect(edge[:association_type]).to eq("has_many")
    end

    it "deduplicates has_many/belongs_to edges into a single edge with both labels" do
      edge = result[:edges].find { |e| e[:from] == "User" && e[:to] == "Post" && e[:association_type] == "has_many" }

      expect(edge).not_to be_nil
      expect(edge[:label]).to eq("posts")
      expect(edge[:reverse_label]).to eq("user")
      expect(edge[:reverse_association_type]).to eq("belongs_to")

      bt_edges = result[:edges].select do |e|
        e[:from] == "Post" && e[:to] == "User" && e[:association_type] == "belongs_to"
      end
      expect(bt_edges).to be_empty
    end

    it "deduplicates HABTM edges between Post and Tag into a single edge with both labels" do
      habtm_edges = result[:edges].select do |e|
        e[:association_type] == "has_and_belongs_to_many" &&
          [e[:from], e[:to]].sort == %w[Post Tag]
      end

      expect(habtm_edges.length).to eq(1)
      edge = habtm_edges.first
      expect(edge[:label]).to eq("tags")
      expect(edge[:reverse_label]).to eq("posts")
    end
  end

  describe "#build with duplicate model names" do
    let(:dup_model_a) do
      double("DupModelA", name: "HABTM_Things", table_name: "things_roles")
    end

    let(:dup_model_b) do
      double("DupModelB", name: "HABTM_Things", table_name: "things_trackers")
    end

    let(:other_model) do
      double("OtherModel", name: "Role", table_name: "roles")
    end

    let(:column_reader) { instance_double(Rails::Schema::Extractor::ColumnReader) }
    let(:association_reader) { instance_double(Rails::Schema::Extractor::AssociationReader) }

    let(:builder_with_dups) do
      described_class.new(column_reader: column_reader, association_reader: association_reader)
    end

    before do
      allow(column_reader).to receive(:read).and_return([])
      allow(association_reader).to receive(:read).with(dup_model_a).and_return(
        [{ from: "HABTM_Things", to: "Role", association_type: "belongs_to",
           label: "role", foreign_key: "role_id", through: nil, polymorphic: false }]
      )
      allow(association_reader).to receive(:read).with(dup_model_b).and_return([])
      allow(association_reader).to receive(:read).with(other_model).and_return([])
    end

    it "assigns unique IDs to models with the same name" do
      result = builder_with_dups.build([dup_model_a, dup_model_b, other_model])
      node_ids = result[:nodes].map { |n| n[:id] }

      expect(node_ids).to contain_exactly("HABTM_Things (things_roles)",
                                          "HABTM_Things (things_trackers)",
                                          "Role")
    end

    it "creates edges with disambiguated IDs" do
      result = builder_with_dups.build([dup_model_a, dup_model_b, other_model])
      edge = result[:edges].find { |e| e[:to] == "Role" }

      expect(edge).not_to be_nil
      expect(edge[:from]).to eq("HABTM_Things (things_roles)")
    end
  end
end
