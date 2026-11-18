# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChaskiqBoot do
  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("DISABLE_AUTOLOAD_APPSTORE").and_return(nil)
  end

  def stub_plugins_table(exists)
    conn = ActiveRecord::Base.connection
    allow(conn).to receive(:table_exists?).and_wrap_original do |original, name|
      name.to_s == "plugins" ? exists : original.call(name)
    end
  end

  it "does not call Plugin.save_all_plugins when the plugins table does not exist" do
    stub_plugins_table(false)
    expect(Plugin).not_to receive(:save_all_plugins)
    expect { ChaskiqBoot.plugin_autoloader }.to output.to_stdout
  end

  it "calls Plugin.save_all_plugins when the plugins table exists" do
    stub_plugins_table(true)
    expect(Plugin).to receive(:save_all_plugins)
    expect { ChaskiqBoot.plugin_autoloader }.to output.to_stdout
  end
end
