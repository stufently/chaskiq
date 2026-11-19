# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middleware::MaintenanceMode do
  it "passes Rack::Lint" do
    app = Rack::Lint.new(described_class.new(nil))
    _, _, body = app.call(Rack::MockRequest.env_for("/"))

    expect { body.each { |_chunk| nil } }.not_to raise_error
  ensure
    body&.close
  end

  it "returns the maintenance page" do
    status, headers, body = described_class.new(nil).call(Rack::MockRequest.env_for("/"))

    expect(status).to eq(200)
    expect(headers["content-type"]).to eq("text/html")
    expect(body.join).to eq(Rails.public_path.join("maintenance.html").read)
  end
end
