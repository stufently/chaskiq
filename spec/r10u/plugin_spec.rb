# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Plugin do
  describe ".save_plugin_files_to_folder" do
    let(:temp_dir) { Dir.mktmpdir("plugin_test") }
    let(:plugin_name) { "TestPlugin" }
    let(:app_package) { AppPackage.new(name: plugin_name) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context "when plugin data is valid" do
      let(:plugin_data) do
        [
          { "file" => "api.rb", "content" => "# Test API\nclass Api; end" },
          { "file" => "presenter.rb", "content" => "# Test Presenter\nclass Presenter; end" }
        ]
      end

      before do
        plugin = instance_double(Plugin, data: plugin_data)
        allow(app_package).to receive(:plugin).and_return(plugin)
        allow(app_package).to receive(:frozen?).and_return(false)
        allow(app_package).to receive(:build_plugin).and_return(plugin)
        allow(AppPackage).to receive(:find_by).with(name: plugin_name).and_return(app_package)

        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
        allow(Rails.autoloaders.main).to receive(:push_dir)
        allow(Rails.autoloaders.main).to receive(:require_dependency)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)
        allow(Rails.logger).to receive(:error)
      end

      it "creates the plugin folder" do
        described_class.save_plugin_files_to_folder(plugin_name)
        expected_path = File.join(temp_dir, "app", "services", "message_apis", plugin_name.underscore)
        expect(Dir.exist?(expected_path)).to be true
      end

      it "writes each file to the plugin folder" do
        described_class.save_plugin_files_to_folder(plugin_name)
        plugin_path = File.join(temp_dir, "app", "services", "message_apis", plugin_name.underscore)
        expect(File.exist?(File.join(plugin_path, "api.rb"))).to be true
        expect(File.exist?(File.join(plugin_path, "presenter.rb"))).to be true
      end

      it "writes correct content to files" do
        described_class.save_plugin_files_to_folder(plugin_name)
        plugin_path = File.join(temp_dir, "app", "services", "message_apis", plugin_name.underscore)
        content = File.read(File.join(plugin_path, "api.rb"))
        expect(content).to eq("# Test API\nclass Api; end")
      end

      it "calls Rails.autoloaders.main.push_dir" do
        expect(Rails.autoloaders.main).to receive(:push_dir).at_least(:once)
        described_class.save_plugin_files_to_folder(plugin_name)
      end

      it "calls Rails.autoloaders.main.require_dependency for each file" do
        expect(Rails.autoloaders.main).to receive(:require_dependency).twice
        described_class.save_plugin_files_to_folder(plugin_name)
      end
    end

    context "when app_package is frozen" do
      before do
        plugin = instance_double(Plugin, data: [])
        allow(app_package).to receive(:plugin).and_return(plugin)
        allow(app_package).to receive(:frozen?).and_return(true)
        allow(AppPackage).to receive(:find_by).with(name: plugin_name).and_return(app_package)
        allow(Rails.logger).to receive(:info)
      end

      it "returns nil without writing files" do
        result = described_class.save_plugin_files_to_folder(plugin_name)
        expect(result).to be_nil
      end

      it "logs skip message" do
        expect(Rails.logger).to receive(:info).with(/Skip installation because it's frozen/)
        described_class.save_plugin_files_to_folder(plugin_name)
      end
    end

    context "when plugin data is invalid" do
      before do
        plugin = instance_double(Plugin, data: "invalid")
        allow(app_package).to receive(:plugin).and_return(plugin)
        allow(app_package).to receive(:frozen?).and_return(false)
        allow(AppPackage).to receive(:find_by).with(name: plugin_name).and_return(app_package)
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
        allow(Rails.logger).to receive(:error)
      end

      it "logs error about invalid data format" do
        expect(Rails.logger).to receive(:error).with(/Invalid plugin data format/)
        described_class.save_plugin_files_to_folder(plugin_name)
      end
    end

    context "when plugin data is nil" do
      before do
        plugin = instance_double(Plugin, data: nil)
        allow(app_package).to receive(:plugin).and_return(plugin)
        allow(app_package).to receive(:frozen?).and_return(false)
        allow(AppPackage).to receive(:find_by).with(name: plugin_name).and_return(app_package)
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
        allow(Rails.logger).to receive(:error)
      end

      it "logs error about invalid data format" do
        expect(Rails.logger).to receive(:error).with(/Invalid plugin data format/)
        described_class.save_plugin_files_to_folder(plugin_name)
      end
    end

    context "when plugin data is empty array" do
      before do
        plugin = instance_double(Plugin, data: [])
        allow(app_package).to receive(:plugin).and_return(plugin)
        allow(app_package).to receive(:frozen?).and_return(false)
        allow(AppPackage).to receive(:find_by).with(name: plugin_name).and_return(app_package)
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
        allow(Rails.logger).to receive(:error)
      end

      it "logs error about invalid data format because empty array is not present" do
        # In Rails, [].present? returns false, so empty array goes to else branch
        expect(Rails.logger).to receive(:error).with(/Invalid plugin data format/)
        described_class.save_plugin_files_to_folder(plugin_name)
      end
    end
  end

  describe ".save_all_plugins" do
    before do
      allow(described_class).to receive(:find_each).and_yield(
        instance_double(Plugin, app_package: instance_double(AppPackage, name: "Plugin1"))
      ).and_yield(
        instance_double(Plugin, app_package: instance_double(AppPackage, name: "Plugin2"))
      )
      allow(described_class).to receive(:save_plugin_files_to_folder)
    end

    it "calls save_plugin_files_to_folder for each plugin" do
      expect(described_class).to receive(:save_plugin_files_to_folder).with("Plugin1")
      expect(described_class).to receive(:save_plugin_files_to_folder).with("Plugin2")
      described_class.save_all_plugins
    end
  end
end
