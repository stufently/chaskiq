# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Presenters configure_hook / initialize_hook case equality" do
  describe MessageApis::ArticleSearch::Presenter do
    let(:app) { FactoryBot.create(:app) }
    let(:package) { double(app: app) }

    it "returns results when field action type is submit and field id is activate-action" do
      ctx = {
        field: { id: "activate-action", action: { type: "submit" } },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:results]).to eq({ foo: "bar", baz: "baaz" })
    end

    it "returns kind unchanged when field action type is click" do
      ctx = {
        field: { id: "activate-action", action: { type: "click" } },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
      expect(result[:results]).to be_nil
    end
  end

  describe MessageApis::Calendly::Presenter do
    let(:app) { FactoryBot.create(:app) }
    let(:package) { double(app: app) }

    it "returns results when field name is set_url and action type is submit with valid url" do
      ctx = {
        field: { name: "set_url", action: { type: "submit" } },
        values: { calendar: "https://calendly.com/test", label: "Book", invitation_text: "Meet us" },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:results][:url]).to eq("https://calendly.com/test")
    end

    it "returns kind unchanged when action type is click" do
      ctx = {
        field: { name: "set_url", action: { type: "click" } },
        values: { calendar: "https://calendly.com/test" },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
    end
  end

  describe MessageApis::ContentShowcase::Presenter do
    it "returns base_schema when field action type is submit and id is announcement" do
      ctx = {
        field: { id: "announcement", action: { type: "submit" } }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
      expect(result[:definitions]).to be_an(Array)
      expect(result[:definitions].any? { |d| d[:text] == "Announcement" }).to eq(true)
    end

    it "returns base definitions when field action type is click" do
      ctx = {
        field: { id: "announcement", action: { type: "click" } }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      base = described_class::AnnouncementRecord.new.base_schema
      expect(result[:definitions]).to eq(base)
    end
  end

  describe MessageApis::OpenAi::Presenter do
    let(:package) { double(settings: { "main_prompt" => "default prompt" }) }

    it "returns initialize kind when field action type is submit and id is add-prompt" do
      ctx = {
        field: { id: "add-prompt", action: { type: "submit" } },
        values: { prompt: "test prompt" },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:results]).to eq({ prompt: "test prompt" })
    end

    it "returns configure kind when field action type is click" do
      ctx = {
        field: { id: "add-prompt", action: { type: "click" } },
        values: { prompt: "test prompt" },
        package: package
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
    end
  end

  describe MessageApis::UiCatalog::Presenter do
    it "configure_hook returns results when field action type is submit and id is aaaaaaaa" do
      ctx = {
        field: { id: "aaaaaaaa", action: { type: "submit" } }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:results]).to eq({ foo: "bar", baz: "baaz" })
    end

    it "configure_hook returns configure kind when field action type is click" do
      ctx = {
        field: { id: "aaaaaaaa", action: { type: "click" } }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
    end

    it "initialize_hook returns content definition when values type is content" do
      ctx = { values: { type: "content" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result[:definitions].first[:type]).to eq("content")
    end

    it "initialize_hook returns button definition when values type is other" do
      ctx = { values: { type: "other" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result[:definitions].first[:type]).to eq("button")
    end
  end

  describe MessageApis::Zoom::Presenter do
    it "returns initialize kind when field name is set_url and action type is submit" do
      ctx = {
        field: { name: "set_url", action: { type: "submit" } },
        values: { zoom_user: "user@example.com" }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:results][:email]).to eq("user@example.com")
    end

    it "returns configure kind when action type is click" do
      ctx = {
        field: { name: "set_url", action: { type: "click" } },
        values: { zoom_user: "user@example.com" }
      }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
    end
  end

  describe MessageApis::Dialog360::Presenter do
    let(:app) { FactoryBot.create(:app) }
    let(:api_klass) { double(retrieve_templates: { "offset" => 0, "total" => 0, "waba_templates" => [] }.to_json) }
    let(:package) { double(message_api_klass: api_klass) }

    it "returns configure kind with results when field name is submit-template and action type is submit" do
      template = { "name" => "hello", "category" => "MARKETING", "components" => [] }
      encoded_id = Base64.encode64(template.to_json)
      ctx = {
        conversation_key: "conv1",
        field: { name: "submit-template", id: encoded_id, action: { type: "submit" }, title: "T" },
        package: package
      }.with_indifferent_access
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
      expect(result[:results]).to include(:id)
    end

    it "returns configure kind without results when action type is click" do
      ctx = {
        conversation_key: "conv1",
        field: { name: "submit-template", id: "abc", action: { type: "click" } },
        package: package
      }.with_indifferent_access
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
      expect(result[:results]).to be_nil
    end
  end

  describe MessageApis::Csat::Presenter do
    let(:csat_package) { double(message_api_klass: double) }

    it "returns initialize kind with csat_buttons when field id is command-confirm" do
      ctx = { field: { "id" => "command-confirm" }, package: csat_package }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("initialize")
      expect(result[:definitions]).to be_an(Array)
      expect(result[:definitions].first[:type]).to eq("single-select")
    end

    it "returns original kind when field id is different" do
      ctx = { field: { "id" => "other-id" }, package: csat_package }
      result = described_class.configure_hook(kind: "configure", ctx: ctx)
      expect(result[:kind]).to eq("configure")
    end
  end

  describe MessageApis::InboxSections::Presenter do
    it "initialize_hook returns content definition when values type is content" do
      ctx = { values: { type: "content", block_type: "tags" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result[:definitions].first[:type]).to eq("content")
    end

    it "initialize_hook returns button definition when values type is other" do
      ctx = { values: { type: "other" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result[:definitions].first[:type]).to eq("button")
    end
  end

  describe MessageApis::Zapier::Presenter do
    it "initialize_hook returns content definition when values type is content" do
      ctx = { values: { type: "content", block_type: "tags" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result[:definitions].first[:type]).to eq("content")
    end

    it "initialize_hook returns nil when values type is other" do
      ctx = { values: { type: "other" } }
      result = described_class.initialize_hook(kind: "initialize", ctx: ctx)
      expect(result).to be_nil
    end
  end
end
