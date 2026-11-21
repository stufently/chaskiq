# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile lookup style specs" do
  let(:conn_double) do
    double("conn").tap do |c|
      allow(c).to receive(:post).and_return(double(success?: true, body: "{}"))
    end
  end

  def participant_with_profile(profile_id)
    profile = double(profile_id: profile_id)
    profiles = double("profiles")
    allow(profiles).to receive(:find_by) { |**kw| profile if kw[:provider] }
    double(external_profiles: profiles, phone: "+1234567890")
  end

  def participant_without_profile(provider)
    profiles = double("profiles")
    allow(profiles).to receive(:find_by).with(provider: provider).and_return(nil)
    double(external_profiles: profiles, phone: "+1234567890")
  end

  def make_part(serialized_text)
    msg = double(as_json: { "serialized_content" => serialized_text })
    double(private_note?: false, message: msg)
  end

  def conversation_with(main_participant)
    double("conversation", main_participant: main_participant)
  end

  describe "Twilio" do
    let(:api) do
      instance = MessageApis::Twilio::Api.new(config: { "api_key" => "k", "api_secret" => "s", "user_id" => "+1555000000" })
      instance.instance_variable_set(:@conn, conn_double)
      instance
    end
    let(:serialized) { MessageApis::BlockManager.serialized_text("hi") }

    describe "#send_message" do
      it "sends To: the profile_id when profile exists" do
        participant = participant_with_profile("+56912345678")
        conv = conversation_with(participant)
        part = make_part(serialized)

        api.send_message(conv, part)

        expect(conn_double).to have_received(:post).with(
          anything,
          hash_including(To: "+56912345678")
        )
      end

      it "returns nil without calling post when no profile" do
        participant = participant_without_profile("twilio")
        conv = conversation_with(participant)
        part = make_part(serialized)

        # Override conn_double to track calls
        tracking_conn = double("tracking_conn")
        allow(tracking_conn).to receive(:post)
        api.instance_variable_set(:@conn, tracking_conn)

        result = api.send_message(conv, part)
        expect(result).to be_nil
        expect(tracking_conn).not_to have_received(:post)
      end
    end

    describe "#prepare_initiator_channel_for" do
      let(:app_double) { double("app", conversations: double(joins: double(where: double(first: nil)))) }
      let(:pkg) { double(app: app_double) }

      it "updates conversation with profile channel" do
        participant = participant_with_profile("twilio_profile_123")
        conv = conversation_with(participant)
        allow(conv).to receive(:update)
        api.instance_variable_set(:@package, pkg)

        api.prepare_initiator_channel_for(conv, pkg)

        expect(conv).to have_received(:update).with(
          conversation_channels_attributes: [{
            provider: "twilio",
            provider_channel_id: "twilio_profile_123"
          }]
        )
      end

      it "raises ActiveRecord::Rollback without profile" do
        participant = participant_without_profile("twilio")
        conv = conversation_with(participant)
        allow(conv).to receive(:update)
        api.instance_variable_set(:@package, pkg)
        allow(api).to receive(:add_participant_to_existing_user).and_return(nil)

        expect { api.prepare_initiator_channel_for(conv, pkg) }
          .to raise_error(ActiveRecord::Rollback)
      end
    end
  end

  describe "MessageBird" do
    let(:api) do
      instance = MessageApis::MessageBird::Api.new(
        config: {
          "api_key" => "k", "api_secret" => "s",
          "user_id" => "+1555000000", "sandbox" => true
        }
      )
      instance.instance_variable_set(:@conn, conn_double)
      instance
    end
    let(:serialized) { MessageApis::BlockManager.serialized_text("hi") }

    describe "#send_message" do
      it "sends to profile_id without + prefix" do
        participant = participant_with_profile("+56912345678")
        conv = conversation_with(participant)
        part = make_part(serialized)

        allow(api).to receive(:delivery_hooks).and_return({})
        api.send_message(conv, part)

        expect(conn_double).to have_received(:post) do |_url, body|
          parsed = JSON.parse(body)
          expect(parsed["to"]).to eq("56912345678")
        end
      end

      it "returns nil without profile" do
        participant = participant_without_profile("message_bird")
        conv = conversation_with(participant)
        part = make_part(serialized)

        allow(api).to receive(:delivery_hooks).and_return({})
        result = api.send_message(conv, part)
        expect(result).to be_nil
      end
    end
  end

  describe "Vonage" do
    let(:api) do
      instance = MessageApis::Vonage::Api.new(
        config: {
          "api_key" => "k", "api_secret" => "s",
          "user_id" => "+1555000000", "sandbox" => true
        }
      )
      instance.instance_variable_set(:@conn, conn_double)
      instance
    end
    let(:serialized) { MessageApis::BlockManager.serialized_text("hi") }

    describe "#send_message" do
      it "sends to with whatsapp type and profile number" do
        participant = participant_with_profile("56912345678")
        conv = conversation_with(participant)
        part = make_part(serialized)

        allow(api).to receive(:delivery_hooks).and_return({})
        api.send_message(conv, part)

        expect(conn_double).to have_received(:post) do |_url, body|
          parsed = JSON.parse(body)
          expect(parsed["to"]).to eq({ "type" => "whatsapp", "number" => "56912345678" })
        end
      end

      it "returns nil without profile" do
        participant = participant_without_profile("vonage")
        conv = conversation_with(participant)
        part = make_part(serialized)

        allow(api).to receive(:delivery_hooks).and_return({})
        result = api.send_message(conv, part)
        expect(result).to be_nil
      end
    end
  end

  describe "Dialog360" do
    let(:api) do
      instance = MessageApis::Dialog360::Api.new(config: { "api_key" => "k", "api_secret" => "s", "user_id" => "+1555000000" })
      instance.instance_variable_set(:@conn, conn_double)
      instance
    end

    describe "#get_profile_for_participant" do
      it "returns profile_id when profile exists" do
        participant = participant_with_profile("dialog360_abc")
        expect(api.get_profile_for_participant(participant)).to eq("dialog360_abc")
      end

      it "returns nil for participant without profile" do
        participant = participant_without_profile("dialog_360")
        expect(api.get_profile_for_participant(participant)).to be_nil
      end

      it "returns nil for nil participant" do
        expect(api.get_profile_for_participant(nil)).to be_nil
      end
    end

    describe "#prepare_initiator_channel_for" do
      let(:app_double) { double("app", conversations: double(joins: double(where: double(first: nil)))) }
      let(:pkg) { double(app: app_double) }

      it "updates conversation with dialog_360 channel when profile exists" do
        participant = participant_with_profile("dialog360_ch_1")
        conv = conversation_with(participant)
        allow(conv).to receive(:update)
        allow(conv).to receive(:main_participant).and_return(participant)
        api.instance_variable_set(:@package, pkg)
        allow(api).to receive(:find_conversation_by_channel).and_return(nil)

        api.prepare_initiator_channel_for(conv, pkg)

        expect(conv).to have_received(:update).with(
          conversation_channels_attributes: [{
            provider: "dialog_360",
            provider_channel_id: "dialog360_ch_1"
          }]
        )
      end

      it "raises ActiveRecord::Rollback when participant has no external profile" do
        participant = participant_without_profile("dialog_360")
        conv = conversation_with(participant)
        allow(conv).to receive(:main_participant).and_return(participant)
        api.instance_variable_set(:@package, pkg)
        allow(api).to receive(:add_participant_to_existing_user).and_return(nil)
        allow(Rails).to receive(:logger).and_return(double(debug: nil))

        expect { api.prepare_initiator_channel_for(conv, pkg) }
          .to raise_error(ActiveRecord::Rollback)
      end
    end
  end

  describe "Telegram" do
    let(:api) do
      instance = MessageApis::Telegram::Api.new(config: { "api_key" => "k", "api_secret" => "s", "user_id" => "+1555000000" })
      instance.instance_variable_set(:@conn, conn_double)
      instance
    end

    describe "#get_profile_for_participant" do
      it "returns profile_id when profile exists" do
        participant = participant_with_profile("tg_profile_1")
        conv = conversation_with(participant)
        expect(api.get_profile_for_participant(conv)).to eq("tg_profile_1")
      end

      it "returns nil when no profile" do
        participant = participant_without_profile("telegram")
        conv = conversation_with(participant)
        expect(api.get_profile_for_participant(conv)).to be_nil
      end
    end
  end

  describe "TwilioPhone" do
    let(:api) do
      instance = MessageApis::TwilioPhone::Api.new(config: { "api_key" => "k", "api_secret" => "s", "user_id" => "+1555000000" })
      instance
    end

    describe "#process_message" do
      it "calls process_incoming_event for StatusCallbackEvent with non-support Caller" do
        params = ActionController::Parameters.new(
          StatusCallbackEvent: "ringing",
          Caller: "+3001234567"
        )
        pkg = double(app: nil)
        result = double("result")
        allow(api).to receive(:process_incoming_event).and_return(result)

        expect(api.process_message(params, pkg)).to eq(result)
      end

      it "does not call process_incoming_event for client:support_agent" do
        params = ActionController::Parameters.new(
          StatusCallbackEvent: "ringing",
          Caller: "client:support_agent"
        )
        pkg = double(app: double(agents: double(find: nil), key: "k"))
        allow(api).to receive(:process_incoming_event)
        allow(Rails).to receive(:logger).and_return(double(debug: nil))

        api.process_message(params, pkg)

        expect(api).not_to have_received(:process_incoming_event)
      end
    end
  end

  describe MessageApis::BlockManager do
    describe ".absolute_url" do
      it "encodes invalid percent sequences" do
        result = described_class.absolute_url("https://cdn.test/a-b/%41%zz?q=1-2#x-y")
        expect(result).to eq("https://cdn.test/a-b/%41%25zz?q=1-2#x-y")
      end
    end
  end
end
