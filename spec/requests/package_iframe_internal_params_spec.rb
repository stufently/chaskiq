# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Package iframe internal params", type: :request do
  let!(:chat_app) { FactoryBot.create(:app) }
  let!(:package) { AppPackage.new(name: "Calendly").tap { |p| p.save!(validate: false) } }
  let!(:integration) do
    AppPackageIntegration.new(app: chat_app, app_package: package).tap { |i| i.save!(validate: false) }
  end

  around do |example|
    original = Rails.application.env_config["action_dispatch.show_exceptions"]
    Rails.application.env_config["action_dispatch.show_exceptions"] = :rescuable
    begin
      example.run
    ensure
      Rails.application.env_config["action_dispatch.show_exceptions"] = original
    end
  end

  it "returns 400 when user is missing" do
    post "/package_iframe_internal/Calendly", params: { data: { field: "f" } }
    expect(response).to have_http_status(400)
  end

  it "returns 400 when user is a string" do
    post "/package_iframe_internal/Calendly", params: { user: "abc", data: { field: "f" } }
    expect(response).to have_http_status(400)
  end

  it "returns 400 when user hash has no id" do
    post "/package_iframe_internal/Calendly", params: { user: { name: "Ann" }, data: { field: "f" } }
    expect(response).to have_http_status(400)
  end
end
