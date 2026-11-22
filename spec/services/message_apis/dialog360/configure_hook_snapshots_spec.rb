# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Dialog360::Presenter do
  snapshots = Rails.root.glob("spec/fixtures/dialog360/configure_hook/*.json").sort

  it "has the 29 configure_hook snapshots" do
    expect(snapshots.size).to eq(29)
  end

  snapshots.each do |path|
    name = path.basename(".json").to_s

    it "configure_hook returns the snapshot #{name}" do
      raw = path.read
      doc = JSON.parse(raw)
      snapshot = JSON.parse(raw, symbolize_names: true)
      stubs = doc.fetch("api")
      calls = []
      record = ->(call, *args) { calls << { "call" => call, "args" => JSON.parse(JSON.generate(args)) } }

      api = double("dialog360 api")
      allow(api).to receive(:retrieve_templates) do |**kw|
        record.call("retrieve_templates", kw)
        stubs.fetch("templates_json")
      end
      allow(api).to receive(:send_template_message) do |**kw|
        record.call("send_template_message", kw)
        JSON.parse(stubs.fetch("send_json"))
      end
      allow(api).to receive(:get_profile_for_participant_label) do |user|
        record.call("get_profile_for_participant_label", user.id)
        stubs.fetch("users").find { |u| u["id"] == user.id }.fetch("label")
      end

      app_users = double("app_users")
      allow(app_users).to receive(:limit) do |num|
        record.call("limit", num)
        app_users
      end
      allow(app_users).to receive(:ransack) do |query|
        record.call("ransack", query)
        app_users
      end
      allow(app_users).to receive(:result) do
        record.call("result")
        stubs.fetch("users").map do |u|
          double("user #{u['id']}", id: u["id"], type: u["type"], display_name: u["display_name"],
                                    email: u["email"], phone: u["phone"])
        end
      end
      package = double("package", message_api_klass: api, app: double("app", key: "app-key-1", app_users: app_users))

      ctx = case doc["ctx_keys"]
            when "indifferent" then doc["ctx"].with_indifferent_access.merge(package: package)
            when "symbol" then snapshot[:ctx].merge(package: package)
            else raise ArgumentError, "unknown ctx_keys #{doc['ctx_keys']}"
            end

      outcome = begin
        { result: described_class.configure_hook(kind: snapshot[:kind], ctx: ctx) }
      rescue StandardError => e
        { raised: { class: e.class.name, message: e.message } }
      end

      expect(snapshot[:case]).to eq(name)
      expect(outcome).to eq(snapshot[:outcome])
      expect(JSON.pretty_generate(outcome)).to eq(JSON.pretty_generate(snapshot[:outcome]))
      expect(calls).to eq(doc["calls"])
    end
  end
end
