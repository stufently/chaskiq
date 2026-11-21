# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalPresenterManager do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.com" }).agent }

  let(:package_double) do
    double(
      app_package: double(
        initialize_url: "https://ext.test/init",
        configure_url: "https://ext.test/configure",
        submit_url: "https://ext.test/submit",
        sheet_url: "https://ext.test/sheet",
        content_url: "https://ext.test/content"
      )
    )
  end

  let(:data) do
    {
      package: package_double,
      ctx: { app: app, current_user: agent }
    }
  end

  before do
    allow(Faraday).to receive(:post) do |url, body, headers|
      @last_url = url
      @last_body = body
      @last_headers = headers
      double(body: '{"kind":"ok"}')
    end
  end

  describe ".post" do
    it "posts JSON and returns parsed body" do
      result = ExternalPresenterManager.post("https://ext.test/test", data)
      expect(result).to eq({ "kind" => "ok" })
      expect(@last_headers).to eq({ "Content-Type" => "application/json" })

      parsed = JSON.parse(@last_body)
      expect(parsed["ctx"]["app"]).to eq({ "key" => app.key, "name" => app.name })
      expect(parsed["ctx"]["current_user"]["email"]).to eq(agent.email)
    end
  end

  describe "hooks" do
    it "initialize_hook posts to initialize_url" do
      ExternalPresenterManager.initialize_hook(data)
      expect(@last_url).to eq("https://ext.test/init")
    end

    it "configure_hook posts to configure_url" do
      ExternalPresenterManager.configure_hook(data)
      expect(@last_url).to eq("https://ext.test/configure")
    end

    it "submit_hook posts to submit_url" do
      ExternalPresenterManager.submit_hook(data)
      expect(@last_url).to eq("https://ext.test/submit")
    end

    it "sheet_hook posts to sheet_url" do
      ExternalPresenterManager.sheet_hook(data)
      expect(@last_url).to eq("https://ext.test/sheet")
    end

    it "content_hook posts to content_url" do
      ExternalPresenterManager.content_hook(data)
      expect(@last_url).to eq("https://ext.test/content")
    end
  end
end
