# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::TwilioPhone::Presenter do
  let(:app) { FactoryBot.create(:app) }
  let(:host) { "https://chat.example.com" }

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with(:host).and_return(host)
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return(host)
  end

  describe ".definitions_for_content" do
    let(:package) { double(id: 77, app: app) }
    let(:conversation_key) { "conv-key-123" }

    context "with an existing conversation and location conversation" do
      let!(:conversation) do
        user = app.add_user(email: "tw@test.com")
        app.start_conversation(
          message: { html_content: "hi", serialized_content: { "content" => [] }.to_json },
          from: user
        )
        Conversation.find_by(key: conversation_key) ||
          app.conversations.last.tap { |c| c.update!(key: conversation_key) }
      end

      let(:ctx) do
        { package: package, conversation_key: conversation_key, lang: "en",
          location: "conversation", current_user: nil }
      end

      it "returns a button with url action and exact options" do
        result = described_class.definitions_for_content(kind: "content", ctx: ctx)
        action = result.last[:action]

        expect(action.keys).to eq(%i[type url options])
        expect(action[:type]).to eq("url")
        expect(action[:url]).to start_with("#{host}/package_iframe/TwilioPhone?token=")
        expected_options = "directories=no,titlebar=no,toolbar=no,location=no," \
                           "status=no,menubar=no,scrollbars=no," \
                           "resizable=no,width=600,height=270,left=200,top=100"
        expect(action[:options]).to eq(expected_options)
      end
    end

    context "with no existing conversation and location conversation" do
      let(:ctx) do
        { package: package, conversation_key: "nonexistent", lang: "en",
          location: "conversation", current_user: nil }
      end

      it "returns a submit action" do
        result = described_class.definitions_for_content(kind: "content", ctx: ctx)
        expect(result.last[:action]).to eq({ type: "submit" })
      end
    end

    context "with location home" do
      let(:ctx) do
        { package: package, conversation_key: conversation_key, lang: "en",
          location: "home", current_user: nil }
      end
      let(:conversation_key) { "any" }

      it "returns a submit action" do
        result = described_class.definitions_for_content(kind: "content", ctx: ctx)
        expect(result.last[:action]).to eq({ type: "submit" })
      end
    end
  end

  describe ".content_definitions" do
    let(:package) do
      double(
        id: 77,
        app: app,
        message_api_klass: double(conferences_list: [])
      )
    end

    let(:ctx) do
      { package: package, conversation_key: "any", lang: "en",
        location: "home", current_user: nil }
    end

    it "returns only the header when conferences list is empty" do
      result = described_class.content_definitions(kind: "conferences_list", ctx: ctx)
      expected = [
        { type: "text", text: "Pick a template", style: "header" }
      ]
      expect(result).to eq(expected)
    end
  end
end
