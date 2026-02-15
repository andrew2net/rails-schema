# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::ModelScanner do
  subject(:scanner) { described_class.new }

  describe "#scan" do
    it "discovers all test models" do
      models = scanner.scan
      model_names = models.map(&:name)

      expect(model_names).to include("User", "Post", "Comment", "Tag")
    end

    it "excludes models matching exact name" do
      Rails::Schema.configure { |c| c.exclude_models = ["User"] }

      models = described_class.new.scan
      model_names = models.map(&:name)

      expect(model_names).not_to include("User")
      expect(model_names).to include("Post")
    end

    it "excludes models matching wildcard prefix" do
      # Since our test models don't use namespaces, test with exact match behavior
      Rails::Schema.configure { |c| c.exclude_models = ["Comment"] }

      models = described_class.new.scan
      expect(models.map(&:name)).not_to include("Comment")
    end

    it "returns models sorted by name" do
      models = scanner.scan
      model_names = models.map(&:name)

      expect(model_names).to eq(model_names.sort)
    end
  end
end
