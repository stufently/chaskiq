# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Package iframe internal", type: :request do
  let!(:chat_app) { FactoryBot.create(:app) }
  let!(:user) { chat_app.add_user(email: "ann@example.com") }
  let!(:package) { AppPackage.new(name: "Calendly").tap { |p| p.save!(validate: false) } }
  let!(:integration) do
    AppPackageIntegration.new(app: chat_app, app_package: package).tap { |i| i.save!(validate: false) }
  end
  let(:captured_opts) { [] }
  let(:presenter) do
    obj = double("presenter")
    allow(obj).to receive(:sheet_view) do |opts|
      captured_opts << opts
      "<p>sheet</p>"
    end
    obj
  end

  before do
    allow_any_instance_of(AppPackageIntegration).to receive(:presenter).and_return(presenter)
  end

  it "renders the presenter output with correct opts" do
    post "/package_iframe_internal/Calendly",
         params: { user: { id: user.id, name: "Ann" }, data: { field: "f" } }
    expect(response).to have_http_status(200)
    expect(response.body).to eq("<p>sheet</p>")
    expect(captured_opts.size).to eq(1)
    opts = captured_opts.first
    expect(opts[:app_key]).to eq(chat_app.key)
    expect(opts[:user]["name"]).to eq("Ann")
    expect(opts[:field]).to eq("f")
  end
end
