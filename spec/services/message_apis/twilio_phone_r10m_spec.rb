# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::TwilioPhone::Api do
  let(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "agent-tp@test.cl" }) }
  let(:agent) { app.agents.first }
  let(:app_package) { AppPackage.find_by(name: "TwilioPhone") }

  let(:pkg) do
    AppPackagesCatalog.update_all
    allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration).and_return({})
    integration = app.app_package_integrations.new(
      api_key: "key",
      api_secret: "secret",
      app_package: app_package
    )
    integration.settings["account_sid"] = "ACtest"
    integration.settings["application_sid"] = "APtest"
    integration.settings["phone_number"] = "+15551234567"
    integration.settings["auth_token"] = "token"
    integration.save!(validate: false)
    integration
  end

  let(:api) { pkg.message_api_klass }

  before do
    pkg
    stub_kredis
    allow(ActionCable.server).to receive(:broadcast)
  end

  def stub_kredis
    @kredis_store = {}
    kredis_store = @kredis_store

    hash_class = Class.new do
      def initialize(store, key)
        @store = store
        @key = key
        @store[@key] ||= {}
      end

      def update(attrs)
        @store[@key].merge!(attrs.transform_keys(&:to_s))
      end

      def [](key)
        @store[@key][key.to_s]
      end

      def values
        @store[@key].values
      end

      def remove
        @store.delete(@key)
      end
    end

    unique_list_class = Class.new do
      def initialize(store, key)
        @store = store
        @key = key
        @store[@key] ||= []
      end

      def elements
        @store[@key]
      end

      def append(val)
        @store[@key] << val unless @store[@key].include?(val)
      end

      def remove(vals)
        @store[@key] -= Array(vals)
      end
    end

    allow(Kredis).to receive(:hash) do |key|
      hash_class.new(kredis_store, key)
    end

    allow(Kredis).to receive(:unique_list) do |key|
      unique_list_class.new(kredis_store, key)
    end
  end

  def base_call_params(overrides = {})
    ActiveSupport::HashWithIndifferentAccess.new({
      "AccountSid" => "ACtest",
      "CallSid" => "CAsid123",
      "CallStatus" => "ringing",
      "Called" => "+19402456692",
      "Caller" => "+56992302305",
      "Direction" => "inbound",
      "From" => "+56992302305",
      "To" => "+19402456692"
    }.merge(overrides))
  end

  describe "process_message" do
    before do
      api.instance_variable_set(:@package, pkg)
    end

    it "routes chaskiq_action=new to conference_call" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      participant.external_profiles.create(provider: "TwilioPhone", profile_id: "+56992302305")
      conversation = app.conversations.create(
        main_participant: participant,
        key: "conv-key-1"
      )

      params = base_call_params("chaskiq_action" => "new", name: conversation.key)
      result = api.process_message(params, pkg)

      expect(result).to include(format: :xml)
    end

    it "routes outbound-api Direction to process_outbound_call" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      conversation = app.conversations.create(
        main_participant: participant,
        conversation_channels_attributes: [
          { provider: "TwilioPhone", provider_channel_id: "CAsid123" }
        ]
      )

      params = base_call_params(Direction: "outbound-api", c: conversation.key)
      result = api.process_message(params, pkg)

      expect(result).to include(format: :xml)
    end

    it "routes StatusCallbackEvent to process_incoming_event when Caller is not support_agent" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      conversation = app.conversations.create(
        main_participant: participant,
        key: "fnTestConv"
      )
      conversation.conversation_channels.create(
        provider: "TwilioPhone",
        provider_channel_id: "CAsid123"
      )

      params = base_call_params(
        StatusCallbackEvent: "participant-hold",
        Caller: "+56992302305",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest",
        SequenceNumber: "0"
      )

      expect { api.process_message(params, pkg) }.not_to raise_error
    end

    it "routes to agent connection when Caller is client:agent" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      conversation = app.conversations.create(
        main_participant: participant,
        key: "conv-agent"
      )
      conversation.conversation_channels.create(
        provider: "TwilioPhone",
        provider_channel_id: "CAsid123"
      )

      params = base_call_params(
        Caller: "client:agent",
        name: conversation.key,
        chaskiq_agent: agent.id.to_s
      )

      result = api.process_message(params, pkg)

      expect(result).to include(format: :xml)
      agent.reload
      expect(agent.available).to eq(false)
    end

    it "routes to process_inbound_call when CallSid and CallStatus are present" do
      params = base_call_params
      result = api.process_message(params, pkg)

      expect(result).to include(format: :xml)
      expect(app.conversations.count).to eq(1)
    end
  end

  describe "process_incoming_call (via inbound)" do
    before do
      api.instance_variable_set(:@package, pkg)
    end

    it "creates a conversation with a TwilioPhone channel for a new caller" do
      params = base_call_params
      api.process_message(params, pkg)

      conv = app.conversations.first
      expect(conv).to be_present
      channel = conv.conversation_channels.find_by(provider: "TwilioPhone")
      expect(channel).to be_present
      expect(channel.provider_channel_id).to eq("CAsid123")
    end

    it "creates a participant with the caller phone number" do
      params = base_call_params
      api.process_message(params, pkg)

      participant = app.conversations.first.main_participant
      expect(participant.phone).to eq("+56992302305")
    end

    it "adds a message with TwilioPhone controls for an inbound call" do
      params = base_call_params
      api.process_message(params, pkg)

      conv = app.conversations.first
      expect(conv.messages.count).to be >= 1
      first_msg = conv.messages.first
      expect(first_msg.messageable).to be_a(ConversationPartBlock)
    end

    it "uses Called for outbound direction" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      conversation = app.conversations.create(
        main_participant: participant,
        conversation_channels_attributes: [
          { provider: "TwilioPhone", provider_channel_id: "CAsid123" }
        ]
      )

      params = base_call_params(Direction: "outbound-api", c: conversation.key)
      api.process_message(params, pkg)

      conv = app.conversations.find_by(key: conversation.key)
      expect(conv).to be_present
      expect(conv.messages.where(messageable_type: "ConversationPartBlock").count).to eq(0)
    end

    it "notifies agents via notify_agent_notification and excludes locked agents" do
      locked = MessageApis::TwilioPhone::Store.locked_agents(app.key)
      locked.append(agent.id.to_s)

      other_agent_role = app.add_agent({ email: "other-tp@test.cl" })
      other_agent = app.agents.find_by(email: "other-tp@test.cl")

      allow(app).to receive(:notify_agent_notification).and_call_original

      params = base_call_params
      api.process_message(params, pkg)

      expect(app).to have_received(:notify_agent_notification).with(other_agent, anything)
      expect(app).not_to have_received(:notify_agent_notification).with(agent, anything)
    end

    it "returns a TwiML response with conference dial" do
      params = base_call_params
      result = api.process_message(params, pkg)

      expect(result[:format]).to eq(:xml)
      expect(result[:response]).to be_a(Twilio::TwiML::VoiceResponse)
      xml = result[:response].to_xml
      expect(xml).to include("<Conference")
    end

    it "assigns agent and skips reassignment when already assigned" do
      participant = app.add_anonymous_user(properties: { name: "Phone User" })
      other_agent_role = app.add_agent({ email: "assigned-tp@test.cl" })
      other_agent = app.agents.find_by(email: "assigned-tp@test.cl")
      conversation = app.conversations.create(
        main_participant: participant,
        assignee: other_agent,
        key: "conv-assigned"
      )
      conversation.conversation_channels.create(
        provider: "TwilioPhone",
        provider_channel_id: "CAsid123"
      )

      params = base_call_params(
        Caller: "client:agent",
        name: conversation.key,
        chaskiq_agent: agent.id.to_s
      )

      api.process_message(params, pkg)

      conversation.reload
      expect(conversation.assignee).to eq(other_agent)
    end
  end

  describe "process_incoming_event" do
    let!(:conversation) do
      participant = pkg.app.add_anonymous_user(properties: { name: "Phone User" })
      conv = pkg.app.conversations.create!(
        main_participant: participant,
        key: "fnEventConv"
      )
      conv.conversation_channels.create!(
        provider: "TwilioPhone",
        provider_channel_id: "CAsid123"
      )
      conv
    end

    before do
      api.instance_variable_set(:@package, pkg)
      allow(ApiChannelNotificatorJob).to receive(:perform_later)
      conference = double("Twilio conference", sid: "CFtest", status: "in-progress", friendly_name: conversation.key)
      resource = double("Twilio conference resource", fetch: conference)
      client = double("Twilio client")
      allow(client).to receive(:conferences).with("CFtest").and_return(resource)
      allow(client).to receive(:conferences).with("CFtest123").and_return(resource)
      allow(api).to receive(:client).and_return(client)
    end

    it "records a message event with the StatusCallbackEvent" do
      params = base_call_params(
        StatusCallbackEvent: "participant-join",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest",
        SequenceNumber: "0"
      )

      api.process_incoming_event(params)

      event_part = conversation.messages.last
      expect(event_part.messageable).to be_a(ConversationPartEvent)
      expect(event_part.messageable.action).to eq("participant-join")
      expect(event_part.messageable.data).to eq("status" => "participant-join")
      expect(event_part.conversation_part_channel_sources.pluck(:provider, :message_source_id))
        .to eq([["TwilioPhone", "bypass-internal-CAsid123-0"]])
    end

    it "stores the ConferenceSid in the data store" do
      params = base_call_params(
        StatusCallbackEvent: "participant-join",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest123",
        SequenceNumber: "0"
      )

      api.process_incoming_event(params)

      stored = MessageApis::TwilioPhone::Store.get_data(conversation.key, :conference_sid)
      expect(stored).to eq("CFtest123")
    end

    it "broadcasts via ActionCable with the exact app key and event type" do
      params = base_call_params(
        StatusCallbackEvent: "participant-join",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest",
        SequenceNumber: "0"
      )

      api.process_incoming_event(params)

      expect(ActionCable.server).to have_received(:broadcast).with(
        "events:#{app.key}",
        type: "/package/TwilioPhone",
        app: app.key,
        payload: params,
        conference: hash_including(conference: hash_including(sid: "CFtest", status: "in-progress")),
        event_type: "INIT",
        agent_id: nil
      )
    end

    it "unlocks agents and modifies the block on conference-end" do
      store = MessageApis::TwilioPhone::Store
      locked = store.locked_agents(app.key)
      locked.append(agent.id.to_s)
      store.set(conversation.key, "CAsid123", agent.id.to_s)

      conversation.add_message(
        from: pkg.app.agents.first,
        controls: {
          app_package: "TwilioPhone",
          schema: [{ type: "content" }],
          type: "app_package",
          wait_for_input: true
        }
      )

      params = base_call_params(
        StatusCallbackEvent: "conference-end",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest",
        SequenceNumber: "3"
      )

      api.process_incoming_event(params)

      expect(locked.elements).to be_empty
      expect(store.hash(conversation.key).values).to be_empty
      expect(store.get_data(conversation.key, :conference_sid)).to be_nil
      block = conversation.message_blocks.last
      expect(block.state).to eq("replied")
      expect(block.blocks["schema"]).to eq([{ "type" => "text", "text" => "Call ended" }])
    end

    it "does not modify agents on participant-hold" do
      agent.update(available: false)

      params = base_call_params(
        StatusCallbackEvent: "participant-hold",
        FriendlyName: conversation.key,
        ConferenceSid: "CFtest",
        SequenceNumber: "1",
        Hold: "true"
      )

      api.process_incoming_event(params)

      agent.reload
      expect(agent.available).to eq(false)
    end
  end
end
