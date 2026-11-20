# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BasePackage do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "resumable#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "test" }) }

  let(:plain_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "plain_test")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end

  let(:resumable_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "resumable_test")
    klass.const_set(:RESUMABLE_DELIVERY, true)
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end

  let(:no_resumable_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "no_resumable_test")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end

  describe "#resumable_delivery?" do
    it "returns false when RESUMABLE_DELIVERY is not defined" do
      pkg = no_resumable_plugin.new(config: {})
      expect(pkg.send(:resumable_delivery?, part)).to be false
    end

    it "returns false when RESUMABLE_DELIVERY is true but no media blocks" do
      pkg = resumable_plugin.new(config: {})
      expect(pkg.send(:resumable_delivery?, part)).to be false
    end
  end

  describe "#delivery_hooks" do
    it "returns only on_failure for non-resumable plugin" do
      pkg = no_resumable_plugin.new(config: {})
      hooks = pkg.send(:delivery_hooks, conversation, part)
      expect(hooks).to have_key(:on_failure)
      expect(hooks).not_to have_key(:on_success)
    end
  end

  describe "#store_message_id for non-resumable plugin" do
    it "stores message_id with nil delivery_index on success" do
      pkg = plain_plugin.new(config: {})
      response = double("resp", success?: true, body: '{"id":"msg-plain"}')
      pkg.send(:store_message_id, part, response)
      source = part.conversation_part_channel_sources.find_by(provider: "plain_test")
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-plain")
      expect(source.delivery_index).to be_nil
    end
  end

  describe "#store_message_id with delivery_index" do
    it "creates a row for a new delivery_index" do
      pkg = resumable_plugin.new(config: {})
      response = double("resp", success?: true, body: '{"id":"msg-idx"}')
      pkg.send(:store_message_id, part, response, delivery_index: 1)
      source = part.conversation_part_channel_sources.find_by(provider: "resumable_test", delivery_index: 1)
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-idx")
    end

    it "does not create duplicate rows for same delivery_index" do
      pkg = resumable_plugin.new(config: {})
      resp1 = double("r1", success?: true, body: '{"id":"first"}')
      resp2 = double("r2", success?: true, body: '{"id":"second"}')
      pkg.send(:store_message_id, part, resp1, delivery_index: 1)
      pkg.send(:store_message_id, part, resp2, delivery_index: 1)
      sources = part.conversation_part_channel_sources.where(provider: "resumable_test", delivery_index: 1)
      expect(sources.count).to eq(1)
    end
  end
end
