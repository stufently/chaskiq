# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Pipedrive::Api do
  include WebMock::API

  let(:api) { described_class.new(config: { "api_secret" => "tok" }) }
  let(:persons_url) { "https://api.pipedrive.com/v1/persons?api_token=tok" }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  describe "#create_person" do
    it "sends the supplied contact fields as JSON" do
      params = { email: "contact@example.com", name: "Ann" }
      stub_request(:post, persons_url).to_return(body: { success: true, data: { id: 5 } }.to_json)

      api.create_person(params: params)

      assert_requested(:post, persons_url, headers: { "Content-Type" => "application/json" }, body: params)
    end
  end

  describe "#register_contact" do
    let(:app) { FactoryBot.create(:app) }
    let(:user) { app.add_user(email: "contact@example.com", name: "Ann") }
    let(:created_person) { { "id" => 5, "name" => "Ann" } }

    it "replaces the external profile when Pipedrive cannot find the saved person" do
      profile = user.external_profiles.create!(provider: "pipedrive", profile_id: "42")
      stub_request(:get, "https://api.pipedrive.com/v1/persons/42?api_token=tok")
        .to_return(body: { success: false, data: nil }.to_json)
      stub_request(:post, persons_url)
        .to_return(body: { success: true, data: created_person }.to_json)

      api.register_contact(user)

      expect(profile.reload).to have_attributes(profile_id: "5", data: created_person)
    end

    it "sends the user's name and saves the new Pipedrive ID" do
      stub_request(:post, persons_url)
        .to_return(body: { success: true, data: created_person }.to_json)

      api.register_contact(user)

      assert_requested(:post, persons_url, body: { email: user.email, name: "Ann" })
      expect(user.external_profiles.find_by!(provider: "pipedrive").profile_id).to eq("5")
    end

    it "leaves the profile without a Pipedrive ID when creation fails" do
      stub_request(:post, persons_url).to_return(body: { success: false, data: nil }.to_json)

      api.register_contact(user)

      expect(user.external_profiles.find_by!(provider: "pipedrive").profile_id).to be_nil
    end
  end
end
