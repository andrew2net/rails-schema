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
end
