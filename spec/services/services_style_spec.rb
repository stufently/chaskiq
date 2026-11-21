# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Services style specs" do
  describe ActionTrigger do
    describe ".process_next_step" do
      let(:app) { double("app", agent_bots: double(first: double("author"))) }
      let(:trigger) do
        paths = [
          { steps: [{ step_uid: 3, controls: {}, messages: [] }] },
          { steps: [{ step_uid: 9, controls: {}, messages: [{ body: "hello" }] }] }
        ]
        double("trigger", id: 1, paths: paths)
      end
      let(:conversation) { double("conversation") }
      let(:trigger_locked) do
        lock = double("lock", value: nil)
        allow(lock).to receive(:value=)
        lock
      end
      let(:message) do
        msg = double("inner_message", blocks: { "next_step_uuid" => "9" })
        double(
          "message",
          trigger_locked: trigger_locked,
          step_id: "1",
          trigger_id: "2",
          message: msg,
          conversation: conversation
        )
      end

      before do
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, nil])
        allow(conversation).to receive(:add_message)
        allow(described_class).to receive(:handle_follow_actions)
      end

      it "finds the step matching next_step_uuid and adds message with step_id 9" do
        described_class.process_next_step(app, message, nil)
        expect(conversation).to have_received(:add_message).with(
          hash_including(step_id: 9)
        )
      end

      it "raises NoMethodError when message.message is nil" do
        allow(message).to receive(:message).and_return(nil)
        expect { described_class.process_next_step(app, message, nil) }
          .to raise_error(NoMethodError)
      end
    end
  end

  describe OriginValidator do
    let(:host) { "http://loc.cl:3002" }

    describe "#valid?" do
      it "returns true when the app list includes the host" do
        validator = described_class.new(app: "http://loc.cl:3002", host: host)
        expect(validator.valid?).to be true
      end

      it "raises NonAcceptedOrigin when host is not in the list" do
        validator = described_class.new(app: "http://other.example.com", host: host)
        expect { validator.valid? }.to raise_error(OriginValidator::NonAcceptedOrigin)
      end

      it "calls validate_domain for each domain in a comma-separated list" do
        validator = described_class.new(
          app: "http://a.com, http://b.com, http://loc.cl:3002",
          host: host
        )
        domains_checked = []
        allow(validator).to receive(:validate_domain) do |d|
          domains_checked << d
          d == "http://loc.cl:3002"
        end
        validator.valid?
        expect(domains_checked).to contain_exactly("http://a.com", "http://b.com", "http://loc.cl:3002")
      end
    end
  end

  describe PaymentServices::Paddle do
    describe "#get_plans" do
      basic = { id: 1, name: "basic", features: [{ name: "chat", active: true }] }.with_indifferent_access
      pro = { id: 2, name: "pro", features: [{ name: "chat", active: true }] }.with_indifferent_access
      let(:local_plans) { [basic, pro] }

      let(:remote_plan_a) do
        double(
          "remote_plan_1",
          id: 1,
          recurring_price: double(USD: 10.0, billing_type: "monthly")
        )
      end

      let(:remote_plan_b) do
        double(
          "remote_plan_2",
          id: 2,
          recurring_price: double(USD: 20.0, billing_type: "monthly")
        )
      end

      let(:remote_plan_unknown) do
        double(
          "remote_unknown",
          id: 999,
          recurring_price: double(USD: 50.0, billing_type: "monthly")
        )
      end

      before do
        allow(Plan).to receive(:all).and_return(local_plans)
        allow(Plan).to receive(:get_by_id) do |id|
          local_plans.find { |p| p[:id] == id || p[:id] == id.to_s }
        end
      end

      it "returns only locally known plans, in order, with local features and name" do
        paddle = described_class.new
        allow(paddle).to receive(:get_data).and_return([remote_plan_a, remote_plan_b, remote_plan_unknown])

        result = paddle.get_plans
        expect(result.size).to eq(2)
        expect(result.pluck(:id)).to eq([1, 2])
        expect(result.first[:name]).to eq("basic")
        expect(result.first[:features]).to eq(local_plans.first[:features])
      end
    end
  end

  describe PluginSchemaValidator do
    def build_validator(nodes)
      v = described_class.new([])
      v.schema = nodes
      v
    end

    describe "#valid?" do
      it "returns true when all nodes are valid" do
        validator = build_validator([double(valid?: true), double(valid?: true)])
        expect(validator.valid?).to be true
      end

      it "returns false when one node is invalid" do
        validator = build_validator([double(valid?: true), double(valid?: false)])
        expect(validator.valid?).to be false
      end

      it "returns false when a node returns nil from valid?" do
        validator = build_validator([double(valid?: true), double(valid?: nil)])
        expect(validator.valid?).to be false
      end

      it "calls valid? on every node including those after an invalid one" do
        node1 = double("n1")
        node2 = double("n2")
        node3 = double("n3")
        allow(node1).to receive(:valid?).and_return(false)
        allow(node2).to receive(:valid?).and_return(true)
        allow(node3).to receive(:valid?).and_return(true)

        validator = build_validator([node1, node2, node3])
        validator.valid?

        expect(node1).to have_received(:valid?)
        expect(node2).to have_received(:valid?)
        expect(node3).to have_received(:valid?)
      end
    end
  end
end
