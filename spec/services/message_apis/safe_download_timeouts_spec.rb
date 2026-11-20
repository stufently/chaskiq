# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::SafeDownload do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
    WebMock.disable!
  end

  describe ".fetch open_timeout" do
    it "sets open_timeout to 5 on the Net::HTTP instance" do
      url = "https://example.com/file.txt"
      stub_request(:get, url).to_return(status: 200, body: "data", headers: { "content-type" => "text/plain" })

      observed_timeouts = []
      original_new = Net::HTTP.method(:new)
      allow(Net::HTTP).to receive(:new) do |*args|
        http = original_new.call(*args)
        real_method = http.method(:open_timeout=)
        allow(http).to receive(:open_timeout=) do |val|
          observed_timeouts << val
          real_method.call(val)
        end
        http
      end

      described_class.fetch(url)
      expect(observed_timeouts).to include(5)
    end
  end
end
