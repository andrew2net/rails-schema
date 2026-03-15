# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../../support/mongoid_test_models"
require "rails/schema/extractor/mongoid/model_scanner"

RSpec.describe Rails::Schema::Extractor::Mongoid::ModelScanner do
  let(:configuration) { Rails::Schema::Configuration.new }
  let(:scanner) { described_class.new(configuration: configuration) }

  describe "#scan" do
    it "discovers classes that include Mongoid::Document" do
      result = scanner.scan

      names = result.map(&:name)
      expect(names).to include("MongoidUser", "MongoidPost", "MongoidComment")
    end

    it "returns models sorted alphabetically" do
      result = scanner.scan

      names = result.map(&:name)
      expect(names).to eq(names.sort)
    end

    it "excludes models matching exact name in exclude_models" do
      configuration.exclude_models = ["MongoidComment"]

      result = scanner.scan

      names = result.map(&:name)
      expect(names).not_to include("MongoidComment")
      expect(names).to include("MongoidUser", "MongoidPost")
    end

    it "excludes models matching wildcard prefix in exclude_models" do
      configuration.exclude_models = ["MongoidC*"]

      result = scanner.scan

      names = result.map(&:name)
      expect(names).not_to include("MongoidComment")
      expect(names).to include("MongoidUser", "MongoidPost")
    end

    it "excludes models matching exclude_model_if proc" do
      configuration.exclude_model_if = ->(model) { model.name.start_with?("MongoidC") }

      result = scanner.scan

      names = result.map(&:name)
      expect(names).not_to include("MongoidComment")
      expect(names).to include("MongoidUser", "MongoidPost")
    end

    it "applies both exclude_models and exclude_model_if" do
      configuration.exclude_models = ["MongoidUser"]
      configuration.exclude_model_if = ->(model) { model.name == "MongoidPost" }

      result = scanner.scan

      names = result.map(&:name)
      expect(names).not_to include("MongoidUser", "MongoidPost")
      expect(names).to include("MongoidComment")
    end

    it "skips classes without a name" do
      anonymous = Class.new { include Mongoid::Document }

      result = scanner.scan

      expect(result).not_to include(anonymous)
    end

    context "when engines are mounted" do
      let(:mock_app) { instance_double("Rails::Application") }
      let(:mock_autoloader) { double("Zeitwerk::Loader") }
      let(:mock_autoloaders) { double("autoloaders", main: mock_autoloader) }
      let(:tmp) { Pathname.new(Dir.mktmpdir) }
      let(:engine_models_path) { tmp.join("engine_models").to_s }
      let(:mock_paths) { double("paths") }
      let(:mock_engine) { double("engine_instance", paths: mock_paths) }

      # Stub Rails::Engine and Rails::Application for the test env
      let!(:engine_base) do
        unless defined?(Rails::Engine)
          stub_class = Class.new
          Rails.const_set(:Engine, stub_class)
        end
        Rails::Engine
      end

      let!(:application_base) do
        unless defined?(Rails::Application)
          stub_class = Class.new(engine_base)
          Rails.const_set(:Application, stub_class)
        end
        Rails::Application
      end

      let(:mock_engine_class) do
        klass = Class.new(engine_base)
        allow(klass).to receive(:instance).and_return(mock_engine)
        klass
      end

      before do
        FileUtils.mkdir_p(tmp.join("app", "models"))
        FileUtils.mkdir_p(engine_models_path)
        allow(Rails).to receive(:application).and_return(mock_app)
        allow(Rails).to receive(:autoloaders).and_return(mock_autoloaders)
        allow(Rails).to receive(:root).and_return(tmp)
        allow(mock_autoloader).to receive(:eager_load_dir)
        allow(mock_paths).to receive(:[]).with("app/models").and_return(double(existent: [engine_models_path]))
        # Force lazy let to register the engine subclass before scan
        mock_engine_class
      end

      after do
        FileUtils.remove_entry(tmp.to_s) if tmp
      end

      it "eager-loads model directories from mounted engines" do
        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(engine_models_path)
      end

      it "skips Rails::Application subclasses" do
        app_class = Class.new(application_base)
        allow(app_class).to receive(:instance).and_return(double("app_instance"))

        scanner.scan

        expect(app_class).not_to have_received(:instance)
      end

      it "handles engine loading errors gracefully" do
        allow(mock_engine_class).to receive(:instance).and_raise(StandardError, "engine boom")

        expect { scanner.scan }.to output(/Could not eager-load engine/).to_stderr
      end

      it "skips engines with no model paths" do
        allow(mock_paths).to receive(:[]).with("app/models").and_return(double(existent: []))

        scanner.scan

        # Only called once for the main app models path, not for the engine
        expect(mock_autoloader).to have_received(:eager_load_dir).once
                                                                 .with(tmp.join("app", "models").to_s)
      end
    end
  end
end
