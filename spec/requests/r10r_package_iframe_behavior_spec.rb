# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe "R10r PackageIframeBehavior", type: :request do
  include WebMock::API

  let!(:chat_app) { FactoryBot.create(:app) }
  let!(:user) { chat_app.add_user(email: "iframe@example.com") }
  let!(:package) { AppPackage.new(name: "Calendly").tap { |p| p.save!(validate: false) } }
  let!(:integration) do
    AppPackageIntegration.new(app: chat_app, app_package: package).tap { |i| i.save!(validate: false) }
  end
  let(:captured_opts) { [] }
  let(:presenter) do
    obj = double("presenter")
    allow(obj).to receive(:sheet_view) do |opts|
      captured_opts << opts
      "<div>sheet</div>"
    end
    obj
  end

  before do
    WebMock.enable!
    allow_any_instance_of(AppPackageIntegration).to receive(:presenter).and_return(presenter)
  end

  after do
    WebMock.reset!
    WebMock.disable!
  end

  describe "package_iframe with token" do
    it "verifies the token and renders the presenter output" do
      token_data = { app_id: chat_app.id, package_id: integration.id }
      token = CHASKIQ_FRAME_VERIFIER.generate(token_data)

      get "/package_iframe/Calendly", params: { token: token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<div>sheet</div>")
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "merges user_token into data when present" do
      token_data = { app_id: chat_app.id, package_id: integration.id }
      user_data = { email: "user@example.com" }
      token = CHASKIQ_FRAME_VERIFIER.generate(token_data)
      user_token = CHASKIQ_FRAME_VERIFIER.generate(user_data)

      get "/package_iframe/Calendly", params: { token: token, user_token: user_token }

      expect(response).to have_http_status(:ok)
      opts = captured_opts.first
      expect(opts[:current_user]).to eq(user_data)
    end

    it "looks up the app by key from verified data" do
      other_app = FactoryBot.create(:app)
      other_package = AppPackage.new(name: "OtherPkg")
      other_package.save!(validate: false)
      other_integration = AppPackageIntegration.new(app: other_app, app_package: other_package)
      allow(other_integration).to receive(:register_hook)
      other_integration.save!(validate: false)

      token_data = { app_id: other_app.id, package_id: other_integration.id }
      token = CHASKIQ_FRAME_VERIFIER.generate(token_data)

      get "/package_iframe/Calendly", params: { token: token }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "package_iframe with data param" do
    let(:enc_data) { { email: "iframe@example.com" } }

    it "renders iframe HTML for external URLs" do
      data = {
        "data" => {
          "app_id" => chat_app.key,
          "enc_data" => enc_data,
          "field" => { "action" => { "url" => "https://external.example.com/embed" } },
          "id" => "Calendly"
        }
      }

      allow_any_instance_of(App).to receive(:decrypt).and_return(enc_data)
      stub_request(:post, "https://external.example.com/embed")
        .to_return(body: "<iframe>external</iframe>")

      get "/package_iframe/Calendly", params: { data: data.to_json }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("iframe")
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "routes internal package_iframe_internal URLs through the presenter" do
      data = {
        "data" => {
          "app_id" => chat_app.key,
          "enc_data" => enc_data,
          "field" => { "action" => { "url" => "/package_iframe_internal/Calendly" } },
          "id" => "Calendly"
        }
      }

      allow_any_instance_of(App).to receive(:decrypt).and_return(enc_data)

      get "/package_iframe/Calendly", params: { data: data.to_json }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<div>sheet</div>")
      opts = captured_opts.first
      expect(opts["app_key"]).to eq(chat_app.key)
    end
  end

  describe "package_iframe_internal" do
    it "renders the presenter output with correct opts" do
      post "/package_iframe_internal/Calendly",
           params: { user: { id: user.id, name: "Ann" }, data: { field: "f" } }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<div>sheet</div>")
      expect(captured_opts.size).to eq(1)
      opts = captured_opts.first
      expect(opts[:app_key]).to eq(chat_app.key)
      expect(opts[:user]["name"]).to eq("Ann")
      expect(opts[:field]).to eq("f")
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "includes conversation_key and message_key when present" do
      post "/package_iframe_internal/Calendly",
           params: {
             user: { id: user.id },
             data: {
               field: "f",
               conversation_key: "conv-123",
               message_key: "msg-456"
             }
           }
      opts = captured_opts.first
      expect(opts[:conversation_key]).to eq("conv-123")
      expect(opts[:message_key]).to eq("msg-456")
    end

    it "returns 400 when user id is missing" do
      post "/package_iframe_internal/Calendly",
           params: { user: { name: "Ann" }, data: { field: "f" } }
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "handle_user_data branches" do
    let(:controller_instance) do
      ctrl = ApplicationController.new
      ctrl.instance_variable_set(:@app, chat_app)
      ctrl
    end

    it "finds user by decrypted email" do
      chat_app.update!(encryption_key: "testkey12345678")
      enc = { email: "iframe@example.com" }
      allow(chat_app).to receive(:decrypt).and_return(enc)

      data = { "data" => { "enc_data" => enc } }
      result = controller_instance.send(:handle_user_data, data)
      expect(result).to eq(user)
    end

    it "finds user by identifier_key when email is not in decrypted data" do
      chat_app.update!(encryption_key: "testkey12345678")
      allow(chat_app).to receive(:decrypt).and_return({})
      allow(chat_app).to receive(:compare_user_identifier).and_return(true)

      data = { "data" => { "enc_data" => { "identifier_key" => "abc", "email" => "iframe@example.com" } } }
      result = controller_instance.send(:handle_user_data, data)
      expect(result).to eq(user)
    end

    it "finds user by session_id from data" do
      chat_app.update!(encryption_key: "testkey12345678")
      allow(chat_app).to receive(:decrypt).and_return({})
      allow(chat_app).to receive(:compare_user_identifier).and_return(false)
      user.update!(session_id: "sess-123")

      data = { "data" => { "enc_data" => {}, "session_id" => "sess-123" } }
      result = controller_instance.send(:handle_user_data, data)
      expect(result).to eq(user)
    end

    it "falls back to cookie session_id when no other match" do
      chat_app.update!(encryption_key: "testkey12345678")
      allow(chat_app).to receive(:decrypt).and_return({})
      allow(chat_app).to receive(:compare_user_identifier).and_return(false)
      user.update!(session_id: "cookie-sess")

      data = { "data" => { "enc_data" => {} } }
      cookie_key = :"chaskiq_session_id_#{chat_app.key.gsub('-', '')}"
      cookies_hash = { cookie_key => "cookie-sess" }
      allow(controller_instance).to receive(:cookies).and_return(cookies_hash)
      result = controller_instance.send(:handle_user_data, data)
      expect(result).to eq(user)
    end

    it "rescues StandardError and falls back to cookie lookup" do
      allow(chat_app).to receive(:decrypt).and_raise(StandardError, "decrypt fail")
      user.update!(session_id: "fallback-sess")

      data = { "data" => { "enc_data" => {} } }
      cookie_key = :"chaskiq_session_id_#{chat_app.key.gsub('-', '')}"
      cookies_hash = { cookie_key => "fallback-sess" }
      allow(controller_instance).to receive(:cookies).and_return(cookies_hash)
      result = controller_instance.send(:handle_user_data, data)
      expect(result).to eq(user)
    end
  end

  describe "handle_url_data" do
    let(:controller_instance) { ApplicationController.new }

    it "prepends HOST for internal package_iframe_internal URLs" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://app.example.com")
      result = controller_instance.send(:handle_url_data, "/package_iframe_internal/Calendly")
      expect(result).to eq("https://app.example.com/package_iframe_internal/Calendly")
    end

    it "returns external URLs unchanged" do
      result = controller_instance.send(:handle_url_data, "https://external.example.com/embed")
      expect(result).to eq("https://external.example.com/embed")
    end
  end

  describe "X-Frame-Options removal" do
    it "removes X-Frame-Options for package_iframe with token" do
      token_data = { app_id: chat_app.id, package_id: integration.id }
      token = CHASKIQ_FRAME_VERIFIER.generate(token_data)

      get "/package_iframe/Calendly", params: { token: token }

      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "removes X-Frame-Options for package_iframe_internal" do
      post "/package_iframe_internal/Calendly",
           params: { user: { id: user.id }, data: { field: "f" } }
      expect(response.headers["X-Frame-Options"]).to be_nil
    end
  end

  describe "layout" do
    it "renders without layout for package_iframe" do
      token_data = { app_id: chat_app.id, package_id: integration.id }
      token = CHASKIQ_FRAME_VERIFIER.generate(token_data)

      get "/package_iframe/Calendly", params: { token: token }

      expect(response.body).not_to include("<html")
    end

    it "renders without layout for package_iframe_internal" do
      post "/package_iframe_internal/Calendly",
           params: { user: { id: user.id }, data: { field: "f" } }
      expect(response.body).not_to include("<html")
    end
  end

  describe "method visibility" do
    it "package_iframe is public on ApplicationController" do
      expect(ApplicationController.public_method_defined?(:package_iframe)).to be true
    end

    it "package_iframe_internal is public on ApplicationController" do
      expect(ApplicationController.public_method_defined?(:package_iframe_internal)).to be true
    end

    it "handle_user_data is public on ApplicationController" do
      expect(ApplicationController.public_method_defined?(:handle_user_data)).to be true
    end

    it "handle_url_data is public on ApplicationController" do
      expect(ApplicationController.public_method_defined?(:handle_url_data)).to be true
    end

    it "iframe_package_request is public on ApplicationController" do
      expect(ApplicationController.public_method_defined?(:iframe_package_request)).to be true
    end
  end
end
