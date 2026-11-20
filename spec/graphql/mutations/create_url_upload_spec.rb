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

  it "uploads files larger than the default safe download limit" do
    url = "https://cdn.example.com/large-file"
    bytes = 16 * 1024 * 1024
    allow(MessageApis::SafeDownload).to receive(:resolve).with("cdn.example.com").and_return(["93.184.216.34"])
    stub_request(:get, url).to_return(body: "x" * bytes)

    result = mutation.resolve(input: OpenStruct.new(url: url))

    expect(ActiveStorage::Blob.find(result.fetch(:direct_upload).fetch(:blob_id)).byte_size).to eq(bytes)
  end

  it "returns a GraphQL error when the download exceeds 100 MB" do
    url = "https://cdn.example.com/too-large"
    allow(MessageApis::SafeDownload).to receive(:resolve).with("cdn.example.com").and_return(["93.184.216.34"])
    stub_request(:get, url).to_return(headers: { "Content-Length" => ((100 * 1024 * 1024) + 1).to_s })

    expect { mutation.resolve(input: OpenStruct.new(url: url)) }
      .to raise_error(GraphQL::ExecutionError, "Unable to download the file")
  end
end
