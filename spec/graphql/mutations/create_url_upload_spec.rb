# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe Mutations::CreateUrlUpload do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  subject(:mutation) { described_class.new(object: nil, context: {}, field: nil) }

  it "rejects a private URL before making any request" do
    url = "https://internal.example.com/file.png"
    allow(MessageApis::SafeDownload).to receive(:resolve).with("internal.example.com").and_return(["192.168.1.10"])
    outbound = stub_request(:any, url)

    expect { mutation.resolve(input: OpenStruct.new(url: url)) }.to raise_error(GraphQL::ExecutionError)
    assert_not_requested(outbound)
  end
end
