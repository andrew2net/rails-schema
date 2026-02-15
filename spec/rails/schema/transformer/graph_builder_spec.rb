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
  end
end
