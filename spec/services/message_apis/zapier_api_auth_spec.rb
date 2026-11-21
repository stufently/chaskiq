# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Zapier::Api do
  let(:app) { FactoryBot.create(:app) }
  let(:package) do
    double(
      app: app,
      access_token: "tok",
      settings: { "user_created" => "https://hooks.zapier.com/catch/123" },
      name: "Acme"
    )
  end

  subject { described_class.new(config: { package: package }) }

  describe "#process_message auth" do
    it "returns ok with app_name when auth key matches" do
      result = subject.send(:process_message, { auth: "tok" }, package)
      expect(result).to eq({ status: :ok, app_name: "my app" })
    end

    it "returns error when auth key does not match" do
      result = subject.send(:process_message, { auth: "wrong" }, package)
      expect(result).to eq({ status: :error, message: "auth key invalid" })
    end
  end

  describe "#event_identifier_available?" do
    it "returns event identifier and url for known event" do
      event = double(action: "users.created")
      result = subject.event_identifier_available?(event)
      expect(result[0]).to eq({ identifier: :user_created, name: "users.created" })
      expect(result[1]).to eq("https://hooks.zapier.com/catch/123")
    end

    it "returns nil pair for unknown event" do
      event = double(action: "unknown.event")
      result = subject.event_identifier_available?(event)
      expect(result).to eq([nil, nil])
    end
  end

  describe "renamed" do
    describe "#event_identifier_and_url" do
      it "returns event identifier and url for known event" do
        event = double(action: "users.created")
        result = subject.event_identifier_and_url(event)
        expect(result[0]).to eq({ identifier: :user_created, name: "users.created" })
        expect(result[1]).to eq("https://hooks.zapier.com/catch/123")
      end

      it "returns nil pair for unknown event" do
        event = double(action: "unknown.event")
        result = subject.event_identifier_and_url(event)
        expect(result).to eq([nil, nil])
      end
    end
  end
end
