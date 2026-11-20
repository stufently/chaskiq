# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middleware::RackBadRequest do
  let(:app) do
    lambda do |env|
      Rack::Request.new(env).GET
      [200, {}, []]
    end
  end

  let(:client) { Rack::MockRequest.new(described_class.new(app)) }

  it "turns a Rack parameter type error into a 400 response" do
    response = client.get("/", "QUERY_STRING" => "item=one&item[]=two", lint: true)

    expect(response.status).to eq(400)
    expect(response.headers["content-type"]).to eq("text/plain")
    expect(response.body).to eq("Bad Request")
  end

  it "turns an invalid query parameter into a 400 response" do
    response = client.get("/", "QUERY_STRING" => "item=%", lint: true)

    expect(response.status).to eq(400)
    expect(response.headers["content-type"]).to eq("text/plain")
    expect(response.body).to eq("Bad Request")
  end

  it "lets unrelated application errors propagate" do
    client = Rack::MockRequest.new(described_class.new(->(_env) { raise ArgumentError, "internal error" }))

    expect { client.get("/") }.to raise_error(ArgumentError, "internal error")
  end
end
