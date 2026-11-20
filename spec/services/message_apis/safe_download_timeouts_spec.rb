# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".fetch open_timeout" do
    it "sets open_timeout to 5 on the HTTP connection" do
      url = "https://example.com/file.txt"
      body_obj = described_class::Body.new("data", content_type: "text/plain")

      stub_request(:get, url).to_return(status: 200, body: "data", headers: { "content-type" => "text/plain" })

      allow(Net::HTTP).to receive(:new).and_call_original
      http_instance = nil
      allow(Net::HTTP).to receive(:new) do |*args|
        http_instance = Net::HTTP.original_new(*args)
        allow(http_instance).to receive(:open_timeout=) do |val|
          http_instance.instance_variable_set(:@open_timeout, val)
        end
        http_instance
      end

      described_class.fetch(url)

      expect(http_instance).to have_received(:open_timeout=).with(5).at_least(:once)
    end
  end
end
