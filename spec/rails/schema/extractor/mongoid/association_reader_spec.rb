# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../support/mongoid_test_models"
require "rails/schema/extractor/mongoid/association_reader"

RSpec.describe Rails::Schema::Extractor::Mongoid::AssociationReader do
  let(:reader) { described_class.new }

  describe "#read" do
    context "with MongoidUser (has_many + embeds_one)" do
      let(:associations) { reader.read(MongoidUser) }

      it "returns an array of association hashes" do
        expect(associations).to be_an(Array)
        expect(associations.length).to eq(2)
      end

      it "reads has_many associations" do
        has_many = associations.find { |a| a[:label] == "posts" }

        expect(has_many[:from]).to eq("MongoidUser")
        expect(has_many[:to]).to eq("MongoidPost")
        expect(has_many[:association_type]).to eq("has_many")
        expect(has_many[:foreign_key]).to eq("user_id")
        expect(has_many[:through]).to be_nil
      end

      it "reads embeds_one associations" do
        embeds_one = associations.find { |a| a[:label] == "profile" }

        expect(embeds_one[:from]).to eq("MongoidUser")
        expect(embeds_one[:to]).to eq("MongoidProfile")
        expect(embeds_one[:association_type]).to eq("embeds_one")
      end
    end

    context "with MongoidPost (belongs_to + embeds_many)" do
      let(:associations) { reader.read(MongoidPost) }

      it "reads belongs_to associations" do
        belongs_to = associations.find { |a| a[:label] == "user" }

        expect(belongs_to[:from]).to eq("MongoidPost")
        expect(belongs_to[:to]).to eq("MongoidUser")
        expect(belongs_to[:association_type]).to eq("belongs_to")
        expect(belongs_to[:foreign_key]).to eq("user_id")
      end

      it "reads embeds_many associations" do
        embeds_many = associations.find { |a| a[:label] == "comments" }

        expect(embeds_many[:from]).to eq("MongoidPost")
        expect(embeds_many[:to]).to eq("MongoidComment")
        expect(embeds_many[:association_type]).to eq("embeds_many")
      end
    end

    context "with MongoidComment (embedded_in)" do
      let(:associations) { reader.read(MongoidComment) }

      it "reads embedded_in associations" do
        embedded_in = associations.find { |a| a[:label] == "post" }

        expect(embedded_in[:from]).to eq("MongoidComment")
        expect(embedded_in[:to]).to eq("MongoidPost")
        expect(embedded_in[:association_type]).to eq("embedded_in")
      end
    end

    context "with has_and_belongs_to_many" do
      let(:model) do
        model = Class.new
        allow(model).to receive(:name).and_return("MongoidArticle")
        allow(model).to receive(:relations).and_return(
          "tags" => StubRelation.new(
            Mongoid::Association::Referenced::HasAndBelongsToMany,
            "MongoidTag",
            "tag_ids",
            nil, nil, "tags"
          )
        )
        model
      end

      it "reads habtm associations" do
        associations = reader.read(model)
        habtm = associations.first

        expect(habtm[:association_type]).to eq("has_and_belongs_to_many")
        expect(habtm[:foreign_key]).to eq("tag_ids")
      end
    end

    context "with polymorphic belongs_to" do
      let(:model) do
        model = Class.new
        allow(model).to receive(:name).and_return("MongoidRating")
        allow(model).to receive(:relations).and_return(
          "ratable" => StubRelation.new(
            Mongoid::Association::Referenced::BelongsTo,
            "Object",
            "ratable_id",
            true, nil, "ratable"
          )
        )
        model
      end

      it "skips polymorphic belongs_to associations" do
        associations = reader.read(model)

        expect(associations).to be_empty
      end
    end

    context "when model.relations raises an error" do
      let(:broken_model) do
        model = Class.new
        allow(model).to receive(:name).and_return("BrokenModel")
        allow(model).to receive(:relations).and_raise(StandardError, "boom")
        model
      end

      it "returns an empty array and warns" do
        expect { reader.read(broken_model) }.to output(/Could not read Mongoid relations/).to_stderr

        expect(reader.read(broken_model)).to eq([])
      end
    end
  end
end
