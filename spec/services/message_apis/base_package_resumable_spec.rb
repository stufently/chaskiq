# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BasePackage do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "resumable#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "test" }) }

  let(:resumable_response) { Struct.new(:success?, :body).new(true, '{"id":"msg-res"}') }
  let(:plain_response) { Struct.new(:success?, :body).new(true, '{"id":"msg-plain"}') }

  describe "M028: resumable plugin does not store with nil delivery_index" do
    let(:resumable_klass) do
      Class.new(described_class) do
        PROVIDER = "resumable_m028"
        RESUMABLE_DELIVERY = true

        def get_message_id(data)
          data["id"]
        end

        def send_message(_conv, _part)
          Struct.new(:success?, :body).new(true, '{"id":"msg-res"}')
        end
      end
    end

    it "notify_part does not create a source row with delivery_index nil" do
      pkg = resumable_klass.new(config: {})
      pkg.send(:notify_part, conversation, part)
      nil_sources = part.conversation_part_channel_sources.where(provider: "resumable_m028", delivery_index: nil)
      expect(nil_sources.count).to eq(0)
    end
  end

  describe "M029: resumable_delivery? returns false without RESUMABLE_DELIVERY" do
    let(:plain_klass) do
      Class.new(described_class) do
        PROVIDER = "plain_m029"

        def get_message_id(data)
          data["id"]
        end
      end
    end

    it "returns false when RESUMABLE_DELIVERY is not defined" do
      pkg = plain_klass.new(config: {})
      expect(pkg.send(:resumable_delivery?, part)).to be false
    end
  end

  describe "M029: delivery_hooks returns :already_sent and :on_success for resumable with media" do
    let(:resumable_klass) do
      Class.new(described_class) do
        PROVIDER = "resumable_m029"
        RESUMABLE_DELIVERY = true

        def get_message_id(data)
          data["id"]
        end
      end
    end

    it "delivery_hooks has :already_sent and :on_success keys for persisted part with media" do
      media_part = conversation.add_message(
        from: recipient,
        message: {
          html_content: "test",
          serialized_content: { content: [{ type: "ImageBlock", url: "http://x.com/i.jpg" }] }.to_json
        }
      )
      pkg = resumable_klass.new(config: {})
      hooks = pkg.send(:delivery_hooks, conversation, media_part)
      expect(hooks).to have_key(:already_sent)
      expect(hooks).to have_key(:on_success)
    end
  end

  describe "M231: non-resumable plugin stores message_id on success" do
    let(:plain_klass) do
      Class.new(described_class) do
        PROVIDER = "plain_m231"

        def get_message_id(data)
          data["id"]
        end

        def send_message(_conv, _part)
          Struct.new(:success?, :body).new(true, '{"id":"msg-plain"}')
        end
      end
    end

    it "notify_part creates a source row with delivery_index nil" do
      pkg = plain_klass.new(config: {})
      pkg.send(:notify_part, conversation, part)
      source = part.conversation_part_channel_sources.find_by(provider: "plain_m231")
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-plain")
      expect(source.delivery_index).to be_nil
    end
  end

  describe "#store_message_id with delivery_index" do
    let(:resumable_klass) do
      Class.new(described_class) do
        PROVIDER = "resumable_idx"
        RESUMABLE_DELIVERY = true

        def get_message_id(data)
          data["id"]
        end
      end
    end

    it "creates a row for a new delivery_index" do
      pkg = resumable_klass.new(config: {})
      response = Struct.new(:success?, :body).new(true, '{"id":"msg-idx"}')
      pkg.send(:store_message_id, part, response, delivery_index: 1)
      source = part.conversation_part_channel_sources.find_by(provider: "resumable_idx", delivery_index: 1)
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-idx")
    end

    it "does not create duplicate rows for same delivery_index" do
      pkg = resumable_klass.new(config: {})
      resp1 = Struct.new(:success?, :body).new(true, '{"id":"first"}')
      resp2 = Struct.new(:success?, :body).new(true, '{"id":"second"}')
      pkg.send(:store_message_id, part, resp1, delivery_index: 1)
      pkg.send(:store_message_id, part, resp2, delivery_index: 1)
      sources = part.conversation_part_channel_sources.where(provider: "resumable_idx", delivery_index: 1)
      expect(sources.count).to eq(1)
    end
  end
end
