# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalApiClient do
  let(:api_url) { "https://ext.test/hook" }
  let(:package_double) { double(app_package: double(api_url: api_url)) }
  let(:config) { { "package" => package_double } }
  let(:client) { ExternalApiClient.new(config: config) }

  let(:fake_conn) do
    double("conn").tap do |c|
      allow(c).to receive(:post) do |url, json, headers|
        @last_url = url
        @last_json = json
        @last_headers = headers
        double(body: '{"ok":true}')
      end
    end
  end

  before { allow(client).to receive(:conn).and_return(fake_conn) }

  describe "#trigger" do
    let(:eventable) { double(to_json: '{"subject":"data"}') }
    let(:event) do
      double(
        action: "created",
        created_at: Time.utc(2026, 1, 2, 3, 4, 5),
        properties: { "key" => "val" },
        eventable: eventable
      ).tap { |e| allow(e).to receive(:as_json) { {} } }
    end

    it "posts to api_url with correct payload and headers" do
      result = client.trigger(event)
      expect(result).to eq({ "ok" => true })
      expect(@last_url).to eq(api_url)
      expect(@last_headers).to eq({ "Content-Type" => "application/json" })

      body = JSON.parse(@last_json)
      expect(body.keys).to match_array(%w[action created_at data])
      expect(body["action"]).to eq("created")
      expect(body["created_at"]).to eq(Time.utc(2026, 1, 2, 3, 4, 5).as_json)
      expect(body["data"]["subject"]).to eq('{"subject":"data"}')
      expect(body["data"]["properties"]).to eq({ "key" => "val" })
    end
  end

  describe "#enqueue_process_event" do
    it "merges package into params and posts" do
      integration = double(as_json: { "id" => 3 })
      client.enqueue_process_event({ "x" => 1 }, integration)

      body = JSON.parse(@last_json)
      expect(body).to eq({ "x" => 1, "package" => { "id" => 3 } })
    end
  end

  describe "#subject_data" do
    it "returns conversation.to_json for Conversation (else branch on BASE)" do
      conversation = Conversation.new(key: "k1")
      result = client.subject_data(conversation)
      expect(result).to eq(conversation.to_json)
    end
  end

  describe "#conn" do
    it "has a timeout of 2" do
      real_client = ExternalApiClient.new(config: config)
      expect(real_client.conn.options.timeout).to eq(2)
    end
  end
end
