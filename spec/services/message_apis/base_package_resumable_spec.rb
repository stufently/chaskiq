# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BasePackage do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "resumable#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "test" }) }

  let(:resumable_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "resumable_test")
    klass.const_set(:RESUMABLE_DELIVERY, true)
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass.define_method(:send_message) { |_conv, _part| double("resp", success?: true, body: '{"id":"msg-res"}') }
    klass
  end
  let(:package) { resumable_plugin.new(config: {}) }

  let(:plain_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "plain_test")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass.define_method(:send_message) { |_conv, _part| double("resp", success?: true, body: '{"id":"msg-plain"}') }
    klass
  end
  let(:plain_package) { plain_plugin.new(config: {}) }

  let(:no_resumable_plugin) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "no_resumable_test")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end
  let(:no_resumable_package) { no_resumable_plugin.new(config: {}) }

  describe "#notify_part with resumable delivery" do
    it "does not store message_id for resumable plugins (delivery_index nil)" do
      package.send(:notify_part, conversation, part)
      sources = part.conversation_part_channel_sources.where(provider: "resumable_test", delivery_index: nil)
      expect(sources.count).to eq(0)
    end
  end

  describe "#resumable_delivery?" do
    it "returns false when RESUMABLE_DELIVERY is not defined" do
      expect(no_resumable_package.send(:resumable_delivery?, part)).to be false
    end
  end

  describe "#delivery_hooks" do
    it "returns already_sent and on_success keys for persisted resumable parts" do
      hooks = package.send(:delivery_hooks, conversation, part)
      expect(hooks).to have_key(:already_sent)
      expect(hooks).to have_key(:on_success)
    end

    it "returns only on_failure for non-resumable plugin" do
      hooks = no_resumable_package.send(:delivery_hooks, conversation, part)
      expect(hooks).to have_key(:on_failure)
      expect(hooks).not_to have_key(:on_success)
    end
  end

  describe "#store_message_id with delivery_index" do
    it "creates a row for a new delivery_index" do
      response = double("resp", success?: true, body: '{"id":"msg-idx"}')
      expect {
        package.send(:store_message_id, part, response, delivery_index: 1)
      }.not_to raise_error
      source = part.conversation_part_channel_sources.find_by(provider: "resumable_test", delivery_index: 1)
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-idx")
    end

    it "stores per delivery_index without extra nil row" do
      response = double("resp", success?: true, body: '{"id":"msg-per"}')
      package.send(:store_message_id, part, response, delivery_index: 1)
      nil_sources = part.conversation_part_channel_sources.where(provider: "resumable_test", delivery_index: nil)
      expect(nil_sources.count).to eq(0)
    end
  end

  describe "#store_message_id with create_or_find_by" do
    it "creates a row for delivery_index and updates on second call" do
      resp1 = double("r1", success?: true, body: '{"id":"first"}')
      resp2 = double("r2", success?: true, body: '{"id":"second"}')
      package.send(:store_message_id, part, resp1, delivery_index: 1)
      package.send(:store_message_id, part, resp2, delivery_index: 1)
      sources = part.conversation_part_channel_sources.where(provider: "resumable_test", delivery_index: 1)
      expect(sources.count).to eq(1)
    end
  end

  describe "#store_message_id for non-resumable plugin" do
    it "stores message_id with nil delivery_index on success" do
      response = double("resp", success?: true, body: '{"id":"msg-nonres"}')
      plain_package.send(:store_message_id, part, response)
      source = part.conversation_part_channel_sources.find_by(provider: "plain_test")
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-nonres")
    end
  end
end
