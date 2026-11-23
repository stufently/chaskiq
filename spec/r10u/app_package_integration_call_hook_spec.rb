# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppPackageIntegration do
  describe "#call_hook" do
    let(:presenter_class) do
      Class.new do
        attr_accessor :last_params

        def initialize_hook(**params)
          @last_params = params
          { kind: "initialize", results: nil, definitions: [] }
        end

        def configure_hook(**params)
          @last_params = params
          { kind: "configure", results: nil, definitions: [] }
        end

        def submit_hook(**params)
          @last_params = params
          { kind: "submit", results: nil, definitions: [] }
        end

        def sheet_hook(**params)
          @last_params = params
          { kind: "frame", results: nil, definitions: [] }
        end

        def content_hook(**params)
          @last_params = params
          { kind: "content", results: nil, definitions: [] }
        end
      end
    end

    let(:presenter) { presenter_class.new }

    let(:app) { App.new(key: "test-app") }
    let(:app_package) { AppPackage.new(name: "TestPackage") }
    let(:integration) do
      i = described_class.new
      i.app = app
      i.app_package = app_package
      i
    end

    before do
      allow(integration).to receive(:presenter).and_return(presenter)
      allow(integration).to receive(:external_package?).and_return(false)
    end

    context "with initialize kind" do
      let(:params) do
        {
          kind: "initialize",
          ctx: { package: integration }
        }
      end

      it "calls presenter.initialize_hook with params" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("initialize")
      end

      it "sets package in ctx" do
        integration.call_hook(params)
        expect(params[:ctx][:package]).to eq(integration)
      end

      it "returns response with initialize kind" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("initialize")
      end

      it "sets ctx field to nil for initialize" do
        integration.call_hook(params)
        expect(params[:ctx][:field]).to be_nil
      end

      it "sets ctx values from response results" do
        allow(presenter).to receive(:initialize_hook).and_return(
          { kind: "initialize", results: { "foo" => "bar" }, definitions: [] }
        )
        integration.call_hook(params)
        expect(params[:ctx][:values]).to eq({ "foo" => "bar" })
      end
    end

    context "with configure kind" do
      let(:params) do
        {
          kind: "configure",
          ctx: { package: integration }
        }
      end

      it "returns response from presenter" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("configure")
      end
    end

    context "with submit kind" do
      let(:params) do
        {
          kind: "submit",
          ctx: { package: integration }
        }
      end

      it "returns response from presenter" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("submit")
      end
    end

    context "with frame kind" do
      let(:params) do
        {
          kind: "frame",
          ctx: { package: integration }
        }
      end

      it "returns response from presenter" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("frame")
      end
    end

    context "with content kind" do
      let(:params) do
        {
          kind: "content",
          ctx: { package: integration }
        }
      end

      it "returns response from presenter" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("content")
      end
    end

    context "with unknown kind" do
      let(:params) do
        {
          kind: "unknown",
          ctx: { package: integration }
        }
      end

      it "raises error about incompatible hook kind" do
        expect { integration.call_hook(params) }.to raise_error("no compatible hook kind")
      end
    end

    context "with external package" do
      before do
        allow(integration).to receive(:external_package?).and_return(true)
      end

      let(:params) do
        {
          kind: "submit",
          ctx: {}
        }
      end

      it "adds package to params" do
        integration.call_hook(params)
        expect(params[:package]).to eq(integration)
      end
    end

    context "with message_key in ctx" do
      let(:message_block) do
        instance_double(ConversationPartBlock).tap do |m|
          allow(m).to receive(:blocks).and_return({})
          allow(m).to receive(:blocks=)
          allow(m).to receive(:save_replied)
        end
      end
      let(:conversation_part) do
        instance_double(ConversationPart).tap do |cp|
          allow(cp).to receive(:message).and_return(message_block)
        end
      end
      let(:conversation_parts) { instance_double(ActiveRecord::Relation) }

      let(:params) do
        {
          kind: "submit",
          ctx: {
            package: integration,
            message_key: "msg-123"
          }
        }
      end

      before do
        allow(app).to receive(:conversation_parts).and_return(conversation_parts)
        allow(conversation_parts).to receive(:find_by).with(key: "msg-123").and_return(conversation_part)
        allow(presenter).to receive(:submit_hook).and_return(
          { kind: "submit", results: { reply: "text" }, definitions: [{ type: "text", text: "hello", style: "paragraph" }] }
        )
      end

      it "finds conversation part by key" do
        expect(conversation_parts).to receive(:find_by).with(key: "msg-123").and_return(conversation_part)
        integration.call_hook(params)
      end

      it "merges schema into message blocks" do
        expect(message_block).to receive(:blocks=).with(hash_including("schema"))
        integration.call_hook(params)
      end

      it "calls save_replied with results" do
        expect(message_block).to receive(:save_replied).with({ reply: "text" })
        integration.call_hook(params)
      end
    end

    context "with invalid schema definitions" do
      let(:params) do
        {
          kind: "submit",
          ctx: { package: integration }
        }
      end

      before do
        allow(presenter).to receive(:submit_hook).and_return(
          { kind: "submit", results: nil, definitions: [{ type: "invalid_type" }] }
        )
      end

      it "raises error about invalid definitions" do
        # Invalid type creates a BaseSchema with nil model, which raises DelegationError
        expect { integration.call_hook(params) }.to raise_error(StandardError)
      end
    end

    context "with blank results" do
      let(:params) do
        {
          kind: "submit",
          ctx: { package: integration }
        }
      end

      before do
        allow(presenter).to receive(:submit_hook).and_return(
          { kind: "submit", results: nil, definitions: [] }
        )
      end

      it "returns response without processing message" do
        result = integration.call_hook(params)
        expect(result[:kind]).to eq("submit")
      end
    end
  end

  describe "#validate_schema!" do
    let(:integration) { described_class.new }

    it "does not raise for valid definitions" do
      definitions = [{ type: "text", text: "hello", style: "paragraph" }]
      expect { integration.validate_schema!(definitions) }.not_to raise_error
    end

    it "raises for invalid definitions" do
      definitions = [{ type: "text" }]
      expect { integration.validate_schema!(definitions) }.to raise_error(StandardError)
    end
  end

  describe "#presenter_hook_response" do
    let(:integration) { described_class.new }
    let(:presenter) do
      Class.new do
        def initialize_hook(**params)
          { kind: "initialize", params: params }
        end

        def configure_hook(**params)
          { kind: "configure", params: params }
        end

        def submit_hook(**params)
          { kind: "submit", params: params }
        end

        def sheet_hook(**params)
          { kind: "frame", params: params }
        end

        def content_hook(**params)
          { kind: "content", params: params }
        end
      end.new
    end

    it "calls initialize_hook for initialize kind" do
      result = integration.presenter_hook_response({ kind: "initialize" }, presenter)
      expect(result[:kind]).to eq("initialize")
    end

    it "calls configure_hook for configure kind" do
      result = integration.presenter_hook_response({ kind: "configure" }, presenter)
      expect(result[:kind]).to eq("configure")
    end

    it "calls submit_hook for submit kind" do
      result = integration.presenter_hook_response({ kind: "submit" }, presenter)
      expect(result[:kind]).to eq("submit")
    end

    it "calls sheet_hook for frame kind" do
      result = integration.presenter_hook_response({ kind: "frame" }, presenter)
      expect(result[:kind]).to eq("frame")
    end

    it "calls content_hook for content kind" do
      result = integration.presenter_hook_response({ kind: "content" }, presenter)
      expect(result[:kind]).to eq("content")
    end

    it "raises for unknown kind" do
      expect do
        integration.presenter_hook_response({ kind: "unknown" }, presenter)
      end.to raise_error("no compatible hook kind")
    end
  end
end
