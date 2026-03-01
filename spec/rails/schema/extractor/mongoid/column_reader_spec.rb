# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../support/mongoid_test_models"
require "rails/schema/extractor/mongoid/column_reader"

RSpec.describe Rails::Schema::Extractor::Mongoid::ColumnReader do
  let(:reader) { described_class.new }

  describe "#read" do
    context "with MongoidUser" do
      let(:columns) { reader.read(MongoidUser) }

      it "returns an array of column hashes" do
        expect(columns).to be_an(Array)
        expect(columns.first).to include(:name, :type, :nullable, :primary, :default)
      end

      it "marks _id as primary" do
        id_col = columns.find { |c| c[:name] == "_id" }

        expect(id_col[:primary]).to be true
        expect(id_col[:type]).to eq("object_id")
      end

      it "maps String type correctly" do
        name_col = columns.find { |c| c[:name] == "name" }

        expect(name_col[:type]).to eq("string")
      end

      it "maps Integer type correctly" do
        age_col = columns.find { |c| c[:name] == "age" }

        expect(age_col[:type]).to eq("integer")
      end

      it "maps Mongoid::Boolean type correctly" do
        active_col = columns.find { |c| c[:name] == "active" }

        expect(active_col[:type]).to eq("boolean")
      end

      it "determines nullable from presence validators" do
        name_col = columns.find { |c| c[:name] == "name" }
        email_col = columns.find { |c| c[:name] == "email" }

        expect(name_col[:nullable]).to be false
        expect(email_col[:nullable]).to be true
      end

      it "includes static defaults" do
        age_col = columns.find { |c| c[:name] == "age" }

        expect(age_col[:default]).to eq(0)
      end
    end

    context "with MongoidPost" do
      let(:columns) { reader.read(MongoidPost) }

      it "maps Time type to datetime" do
        col = columns.find { |c| c[:name] == "published_at" }

        expect(col[:type]).to eq("datetime")
      end

      it "maps Array type correctly" do
        col = columns.find { |c| c[:name] == "tags" }

        expect(col[:type]).to eq("array")
      end

      it "formats Proc defaults as (dynamic)" do
        col = columns.find { |c| c[:name] == "tags" }

        expect(col[:default]).to eq("(dynamic)")
      end

      it "maps Float type correctly" do
        col = reader.read(MongoidComment).find { |c| c[:name] == "rating" }

        expect(col[:type]).to eq("float")
      end
    end

    context "when model.fields raises an error" do
      let(:broken_model) do
        model = Class.new
        allow(model).to receive(:name).and_return("BrokenModel")
        allow(model).to receive(:fields).and_raise(StandardError, "boom")
        model
      end

      it "returns an empty array and warns" do
        expect { reader.read(broken_model) }.to output(/Could not read Mongoid fields/).to_stderr

        expect(reader.read(broken_model)).to eq([])
      end
    end
  end
end
