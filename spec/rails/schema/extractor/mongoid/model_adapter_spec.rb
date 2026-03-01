# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../support/mongoid_test_models"
require "rails/schema/extractor/mongoid/model_adapter"

RSpec.describe Rails::Schema::Extractor::Mongoid::ModelAdapter do
  let(:adapter) { described_class.new(MongoidUser) }

  describe "#name" do
    it "delegates to the model" do
      expect(adapter.name).to eq("MongoidUser")
    end
  end

  describe "#table_name" do
    it "returns the collection name as a string" do
      expect(adapter.table_name).to eq("mongoid_users")
    end
  end

  describe "#model" do
    it "exposes the underlying model" do
      expect(adapter.model).to eq(MongoidUser)
    end
  end

  describe "method delegation" do
    it "forwards unknown methods to the underlying model" do
      expect(adapter.fields).to eq(MongoidUser.fields)
    end

    it "responds to methods the model responds to" do
      expect(adapter).to respond_to(:fields)
      expect(adapter).to respond_to(:relations)
    end

    it "raises NoMethodError for methods neither adapter nor model respond to" do
      expect { adapter.nonexistent_method }.to raise_error(NoMethodError)
    end
  end
end
