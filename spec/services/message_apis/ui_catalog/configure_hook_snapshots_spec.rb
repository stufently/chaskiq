# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::UiCatalog::Presenter do
  snapshots = Rails.root.glob("spec/fixtures/ui_catalog/configure_hook/*.json").sort

  it "has the 32 configure_hook snapshots" do
    expect(snapshots.size).to eq(32)
  end

  snapshots.each do |path|
    name = path.basename(".json").to_s

    it "configure_hook returns the snapshot #{name}" do
      snapshot = JSON.parse(path.read, symbolize_names: true)
      ctx = case snapshot[:ctx_keys]
            when "symbol" then snapshot[:ctx]
            when "string" then snapshot[:ctx].deep_stringify_keys
            else raise ArgumentError, "unknown ctx_keys #{snapshot[:ctx_keys]}"
            end

      result = described_class.configure_hook(kind: snapshot[:kind], ctx: ctx)

      expect(snapshot[:case]).to eq(name)
      expect(result).to eq(snapshot[:result])
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(snapshot[:result]))
    end
  end
end
