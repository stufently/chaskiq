# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".fetch open_timeout" do
    it "sets open_timeout to 5 on the HTTP connection" do
      url = "https://example.com/file.txt"
      stub_request(:get, url).to_return(status: 200, body: "data", headers: { "content-type" => "text/plain" })

      timeouts = []
      allow_any_instance_of(Net::HTTP).to receive(:open_timeout=) do |http, val|
        timeouts << val
        http.instance_variable_set(:@open_timeout, val)
      end

      described_class.fetch(url)
      expect(timeouts).to include(5)
    end
  end
end
