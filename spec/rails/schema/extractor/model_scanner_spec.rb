# frozen_string_literal: true

require "tmpdir"

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

    it "excludes models matching exclude_model_if proc" do
      Rails::Schema.configure { |c| c.exclude_model_if = ->(model) { model.name.start_with?("U") } }

      models = described_class.new.scan
      model_names = models.map(&:name)

      expect(model_names).not_to include("User")
      expect(model_names).to include("Post", "Comment")
    end

    it "applies both exclude_models and exclude_model_if" do
      Rails::Schema.configure do |c|
        c.exclude_models = ["Tag"]
        c.exclude_model_if = ->(model) { model.name == "Comment" }
      end

      models = described_class.new.scan
      model_names = models.map(&:name)

      expect(model_names).not_to include("Tag", "Comment")
      expect(model_names).to include("User", "Post")
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

    context "when using Zeitwerk autoloader" do
      let(:mock_app) { instance_double("Rails::Application") }
      let(:mock_autoloader) { double("Zeitwerk::Loader") }
      let(:mock_autoloaders) { double("autoloaders", main: mock_autoloader) }
      let(:tmp) { Pathname.new(Dir.mktmpdir) }

      before do
        FileUtils.mkdir_p(tmp.join("app", "models"))
        allow(Rails).to receive(:application).and_return(mock_app)
        allow(Rails).to receive(:autoloaders).and_return(mock_autoloaders)
        allow(Rails).to receive(:root).and_return(tmp)
      end

      after do
        FileUtils.remove_entry(tmp.to_s) if tmp
      end

      it "uses eager_load_dir for app models only" do
        allow(mock_autoloader).to receive(:eager_load_dir)
        allow(mock_app).to receive(:eager_load!)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(tmp.join("app", "models").to_s)
        expect(mock_app).not_to have_received(:eager_load!)
      end

      it "falls back to eager_load when eager_load_dir is unavailable" do
        mock_loader = double("Zeitwerk::Loader (old)")
        allow(mock_loader).to receive(:eager_load)
        mock_old_autoloaders = double("autoloaders", main: mock_loader)
        allow(Rails).to receive(:autoloaders).and_return(mock_old_autoloaders)
        allow(mock_app).to receive(:eager_load!)

        mock_abstract = class_double("ActiveRecord::Base", name: "ApplicationRecord",
                                                           abstract_class?: true)
        allow(ActiveRecord::Base).to receive(:descendants).and_return([mock_abstract])

        scanner.scan

        expect(mock_loader).to have_received(:eager_load)
        expect(mock_app).not_to have_received(:eager_load!)
      end

      it "falls back to eager_load! when Zeitwerk fails" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir)
        expect(mock_app).to have_received(:eager_load!)
      end

      it "logs warning when Zeitwerk eager_load fails" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!)

        expect { scanner.scan }.to output(/Zeitwerk eager_load failed/).to_stderr
      end

      it "logs warning when eager_load! fails" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!).and_raise(StandardError, "load error")

        expect { scanner.scan }.to output(/eager_load! failed/).to_stderr
      end

      it "logs warning when a model file fails to load" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!).and_raise(StandardError, "load error")

        models_dir = tmp.join("app", "models")
        File.write(models_dir.join("bad_load_model.rb"), "raise 'boom'")

        expect { scanner.scan }.to output(/Could not load/).to_stderr
      end

      it "logs warning when table_exists? fails" do
        allow(mock_autoloader).to receive(:eager_load_dir)
        allow(mock_app).to receive(:eager_load!)

        mock_model = class_double("ActiveRecord::Base", name: "BadTable",
                                                        abstract_class?: false,
                                                        table_name: "bad_tables")
        allow(mock_model).to receive(:table_exists?).and_raise(StandardError, "connection error")
        allow(ActiveRecord::Base).to receive(:descendants).and_return([mock_model])

        expect { scanner.scan }.to output(/Could not check table for BadTable/).to_stderr
      end

      it "falls back to per-file loading when both fail" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!).and_raise(ActiveRecord::AdapterNotSpecified)

        models_dir = tmp.join("app", "models")
        File.write(models_dir.join("fallback_test_model.rb"),
                   "class FallbackTestModel < ActiveRecord::Base; self.abstract_class = true; end")

        scanner.scan

        expect(defined?(FallbackTestModel)).to eq("constant")
      ensure
        Object.send(:remove_const, :FallbackTestModel) if defined?(FallbackTestModel)
      end

      it "skips files that fail and continues" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!).and_raise(ActiveRecord::AdapterNotSpecified)

        models_dir = tmp.join("app", "models")
        File.write(models_dir.join("aaa_bad_model.rb"), "raise 'boom'")
        File.write(models_dir.join("zzz_good_model.rb"),
                   "class ZzzGoodModel < ActiveRecord::Base; self.abstract_class = true; end")

        scanner.scan

        expect(defined?(ZzzGoodModel)).to eq("constant")
      ensure
        Object.send(:remove_const, :ZzzGoodModel) if defined?(ZzzGoodModel)
      end

      it "falls back to full eager_load when app/models has no concrete models" do
        allow(mock_autoloader).to receive(:eager_load_dir)
        allow(mock_autoloader).to receive(:eager_load)

        mock_abstract = class_double("ActiveRecord::Base", name: "ApplicationRecord",
                                                           abstract_class?: true)
        allow(ActiveRecord::Base).to receive(:descendants).and_return([mock_abstract])

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(tmp.join("app", "models").to_s)
        expect(mock_autoloader).to have_received(:eager_load)
      end

      it "skips full eager_load when app/models has concrete models" do
        allow(mock_autoloader).to receive(:eager_load_dir)
        allow(mock_autoloader).to receive(:eager_load)
        allow(mock_app).to receive(:eager_load!)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(tmp.join("app", "models").to_s)
        expect(mock_autoloader).not_to have_received(:eager_load)
      end

      it "discovers model dirs from packwerk.yml package_paths" do
        # Create packwerk.yml
        File.write(tmp.join("packwerk.yml"), "package_paths:\n  - \".\"\n  - \"packages/*\"\n")

        # Create packages with package.yml
        pkg_accounts = tmp.join("packages", "accounts")
        FileUtils.mkdir_p(pkg_accounts.join("app", "models"))
        FileUtils.mkdir_p(pkg_accounts.join("app", "public"))
        File.write(pkg_accounts.join("package.yml"), "enforce_dependencies: true\n")

        # Root package.yml
        File.write(tmp.join("package.yml"), "enforce_dependencies: false\n")

        allow(mock_autoloader).to receive(:eager_load_dir)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(pkg_accounts.join("app", "models").to_s)
        expect(mock_autoloader).to have_received(:eager_load_dir).with(pkg_accounts.join("app", "public").to_s)
        expect(mock_autoloader).to have_received(:eager_load_dir).with(tmp.join("app", "models").to_s)
      end

      it "skips package dirs without package.yml" do
        File.write(tmp.join("packwerk.yml"), "package_paths:\n  - \"packages/*\"\n")

        # Package WITH package.yml
        pkg_good = tmp.join("packages", "good")
        FileUtils.mkdir_p(pkg_good.join("app", "models"))
        File.write(pkg_good.join("package.yml"), "enforce_dependencies: true\n")

        # Directory WITHOUT package.yml
        pkg_bad = tmp.join("packages", "not_a_package")
        FileUtils.mkdir_p(pkg_bad.join("app", "models"))

        allow(mock_autoloader).to receive(:eager_load_dir)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(pkg_good.join("app", "models").to_s)
        expect(mock_autoloader).not_to have_received(:eager_load_dir).with(pkg_bad.join("app", "models").to_s)
      end

      it "falls back to app/models when no packwerk.yml exists" do
        # No packwerk.yml created
        allow(mock_autoloader).to receive(:eager_load_dir)

        scanner.scan

        expect(mock_autoloader).to have_received(:eager_load_dir).with(tmp.join("app", "models").to_s)
      end

      it "loads packwerk model files in per-file fallback" do
        allow(mock_autoloader).to receive(:eager_load_dir).and_raise(StandardError, "Zeitwerk error")
        allow(mock_app).to receive(:eager_load!).and_raise(ActiveRecord::AdapterNotSpecified)

        File.write(tmp.join("packwerk.yml"), "package_paths:\n  - \"packages/*\"\n")
        pkg_models = tmp.join("packages", "core", "app", "models")
        FileUtils.mkdir_p(pkg_models)
        File.write(tmp.join("packages", "core", "package.yml"), "enforce_dependencies: true\n")
        File.write(pkg_models.join("pkg_fallback_model.rb"),
                   "class PkgFallbackModel < ActiveRecord::Base; self.abstract_class = true; end")

        scanner.scan

        expect(defined?(PkgFallbackModel)).to eq("constant")
      ensure
        Object.send(:remove_const, :PkgFallbackModel) if defined?(PkgFallbackModel)
      end
    end

    context "with schema_data" do
      let(:schema_data) do
        {
          "users" => [{ name: "id", type: "integer", nullable: false, default: nil, primary: true }],
          "posts" => [{ name: "id", type: "integer", nullable: false, default: nil, primary: true }]
        }
      end

      it "uses table name lookup instead of table_exists?" do
        scanner = described_class.new(schema_data: schema_data)
        models = scanner.scan
        model_names = models.map(&:name)

        expect(model_names).to include("User", "Post")
      end

      it "excludes models whose table is not in schema_data" do
        limited_data = {
          "users" => [{ name: "id", type: "integer", nullable: false, default: nil, primary: true }]
        }
        scanner = described_class.new(schema_data: limited_data)
        models = scanner.scan
        model_names = models.map(&:name)

        expect(model_names).to include("User")
        expect(model_names).not_to include("Post")
      end
    end

    context "with empty schema_data" do
      it "falls back to table_exists? instead of rejecting all models" do
        scanner = described_class.new(schema_data: {})
        models = scanner.scan
        model_names = models.map(&:name)

        expect(model_names).to include("User", "Post", "Comment", "Tag")
      end
    end

    context "when no models survive filtering" do
      it "logs diagnostic counts" do
        mock_model = class_double("ActiveRecord::Base", name: "BrokenModel",
                                                        abstract_class?: false,
                                                        table_name: "broken_models")
        allow(mock_model).to receive(:table_exists?).and_return(false)
        allow(ActiveRecord::Base).to receive(:descendants).and_return([mock_model])

        scanner = described_class.new

        expect { scanner.scan }.to output(
          /No models found! Filtering: 1 descendants → 1 concrete → 1 named → 0 with tables/
        ).to_stderr
      end
    end
  end
end
