# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Global hook provider", type: :request do
  let!(:package) { AppPackage.new(name: "Slack").tap { |p| p.save!(validate: false) } }
  let(:calls) { [] }

  before do
    allow_any_instance_of(AppPackage).to receive(:process_global_hook) do |_pkg, params|
      calls << [package.id, params["provider"]]
      "pong"
    end
  end

  it "processes POST with path provider param" do
    post "/api/v1/hooks/global/slack", params: { provider: "other", foo: "bar" }
    expect(response).to have_http_status(200)
    expect(response.body).to eq("pong")
    expect(calls).to eq([[package.id, "slack"]])
  end

  it "processes GET with path provider param" do
    get "/api/v1/hooks/global/slack"
    expect(response).to have_http_status(200)
    expect(response.body).to eq("pong")
  end
end
