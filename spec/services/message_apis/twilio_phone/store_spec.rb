# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::TwilioPhone::Store do
  let(:conv_key) { "conv:mut-test-#{SecureRandom.hex(4)}" }

  after do
    Kredis.hash(described_class.send(:namespace, "#{conv_key}/data")).del
    described_class.locked_agents(conv_key).clear
    described_class.del_callblock("#{described_class.send(:namespace, conv_key)}/callblock")
  rescue StandardError
    nil
  end

  it "uses /twilio_phone/ as namespace prefix" do
    expect(described_class.send(:namespace, conv_key)).to start_with("/twilio_phone/")
    expect(described_class.send(:namespace, conv_key)).to eq("/twilio_phone/#{conv_key}")
  end

  it "stores and retrieves data via Kredis hash" do
    described_class.set_data(conv_key, "agent_key", "agent_value")
    expect(described_class.get_data(conv_key, "agent_key")).to eq("agent_value")
  end

  it "uses unique_list for locked_agents to prevent duplicates" do
    list = described_class.locked_agents(conv_key)
    list.append("agent1")
    list.append("agent1")
    expect(list.elements.count("agent1")).to eq(1)
  end

  it "reads callblock value as a string" do
    cb_key = "#{described_class.send(:namespace, conv_key)}/callblock"
    described_class.set_callblock(cb_key, "http://example.com/callback")
    expect(described_class.callblock(cb_key)).to eq("http://example.com/callback")
  end

  it "stores data in a namespaced Redis key" do
    described_class.set_data(conv_key, "ns_test", "value")
    raw_redis = Redis.new(url: ENV.fetch("REDIS_URL"))
    namespaced_key = described_class.send(:namespace, "#{conv_key}/data")
    expect(raw_redis.exists?(namespaced_key)).to be true
    raw_redis.del(namespaced_key)
    raw_redis.close
  end

  it "stores data under a key with /data suffix" do
    described_class.set_data(conv_key, "path_test", "v")
    raw_redis = Redis.new(url: ENV.fetch("REDIS_URL"))
    expected_key = described_class.send(:namespace, "#{conv_key}/data")
    expect(raw_redis.type(expected_key)).to eq("hash")
    raw_redis.del(expected_key)
    raw_redis.close
  end

  it "get_values reads from the same /data path as set_data writes" do
    described_class.set_data(conv_key, "gv_key", "gv_val")
    values = described_class.get_values("#{conv_key}/data")
    expect(values["gv_key"]).to eq("gv_val")
  end

  it "retrieves all values from the hash" do
    described_class.set_data(conv_key, "k1", "v1")
    described_class.set_data(conv_key, "k2", "v2")
    values = described_class.get_values("#{conv_key}/data")
    expect(values).to include("k1" => "v1", "k2" => "v2")
  end

  it "locked_agents key ends with /locked_agents/<key>" do
    list = described_class.locked_agents("myapp")
    redis_key = list.key
    expect(redis_key).to end_with("/locked_agents/myapp")
  end

  it "locked_agents data written via raw Kredis.unique_list is visible" do
    raw_list = Kredis.unique_list("/twilio_phone//locked_agents/rawtest")
    raw_list.append("agent-x")
    list = described_class.locked_agents("rawtest")
    expect(list.elements).to include("agent-x")
  ensure
    raw_list&.clear
  end

  it "del_callblock removes the key entirely" do
    cb_key = "#{described_class.send(:namespace, conv_key)}/callblock"
    described_class.set_callblock(cb_key, "http://example.com/cb")
    described_class.del_callblock(cb_key)
    expect(Kredis.string(cb_key).assigned?).to be false
  end
end
