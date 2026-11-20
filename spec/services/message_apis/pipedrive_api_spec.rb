# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Pipedrive::Api do
  include WebMock::API

  let(:app) { FactoryBot.create(:app) }
  let(:api) { described_class.new(config: { "api_secret" => "tok" }) }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  describe "#create_person" do
    it "returns parsed JSON response" do
      stub_request(:post, "https://api.pipedrive.com/v1/persons?api_token=tok")
        .to_return(status: 200, body: { success: true, data: { id: 1 } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = api.create_person(params: { email: "test@test.cl", name: "Test" })
      expect(result).to be_a(Hash)
      expect(result["success"]).to be true
      expect(result["data"]["id"]).to eq(1)
    end
  end

  describe "#delete_webhook" do
    it "returns response with status 200" do
      stub_request(:delete, "https://api.pipedrive.com/v1/webhooks/7?api_token=tok")
        .to_return(status: 200, body: { success: true }.to_json)

      response = api.delete_webhook(7)
      expect(response.status).to eq(200)
    end
  end

  describe "#register_contact" do
    let(:user) { app.add_user(email: "contact@test.cl", first_name: "Contact") }

    context "when find response has data" do
      it "saves data in external profile" do
        profile = user.external_profiles.create!(provider: "pipedrive", profile_id: "42")

        stub_request(:get, "https://api.pipedrive.com/v1/persons/42?api_token=tok")
          .to_return(status: 200, body: { success: true, data: { id: 42, name: "Found" } }.to_json)

        api.register_contact(user)
        profile.reload
        expect(profile.data).to eq({ "id" => 42, "name" => "Found" })
      end
    end

    context "when find response data is null" do
      it "raises NoMethodError and does not touch profile data" do
        profile = user.external_profiles.create!(
          provider: "pipedrive", profile_id: "42",
          data: { "id" => 42, "name" => "Old" }
        )

        stub_request(:get, "https://api.pipedrive.com/v1/persons/42?api_token=tok")
          .to_return(status: 200, body: { success: true, data: nil }.to_json)

        expect { api.register_contact(user) }.to raise_error(NoMethodError)
        profile.reload
        expect(profile.data).to eq({ "id" => 42, "name" => "Old" })
      end
    end
  end
end
