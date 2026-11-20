# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".fetch open_timeout" do
    it "sets open_timeout to 5 on the HTTP connection" do
      url = "https://example.com/file.txt"
      stub_request(:get, url).to_return(status: 200, body: "data", headers: { "content-type" => "text/plain" })

      timeouts = []
      original_new = Net::HTTP.method(:new)
      allow(Net::HTTP).to receive(:new) do |*args|
        http = original_new.call(*args)
        allow(http).to receive(:open_timeout=) do |val|
          timeouts << val
          http.instance_variable_set(:@open_timeout, val)
        end
        allow(http).to receive(:request) do |req, &block|
          resp = Net::HTTPOK.new("1.1", 200, "OK")
          allow(resp).to receive(:body).and_return("data")
          allow(resp).to receive(:content_length).and_return(4)
          allow(resp).to receive(:read_body) { |&blk| blk.call("data") }
          allow(resp).to receive(:[]).and_return("text/plain")
          block.call(resp) if block
          resp
        end
        http
      end

      described_class.fetch(url)
      expect(timeouts).to include(5)
    end
  end
end
