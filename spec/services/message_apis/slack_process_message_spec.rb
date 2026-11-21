# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Slack::Api do
  let(:app) { FactoryBot.create(:app) }

  subject { described_class.new(config: { "access_token" => "xoxb-test" }) }

  before do
    allow(subject).to receive(:authorize_bot!).and_return(true)
    allow(subject).to receive(:find_conversation_by_slack_ts).and_return(nil)
  end

  describe "#process_message" do
    it "does not search for conversation when subtype is channel_join" do
      event = { "subtype" => "channel_join", "thread_ts" => "123.456", "ts" => "123.789", "text" => "hi" }
      expect(subject).not_to receive(:find_conversation_by_slack_ts)
      subject.send(:process_message, event)
    end

    it "does not search for conversation when text is the Chaskiq notification" do
      event = { "thread_ts" => "123.456", "ts" => "123.789", "text" => "New conversation from Chaskiq" }
      expect(subject).not_to receive(:find_conversation_by_slack_ts)
      subject.send(:process_message, event)
    end
  end

  describe "#process_blocks" do
    it "includes one extra block for an image block" do
      data = {
        "text" => "hello",
        "blocks" => [
          { "type" => "image", "image_url" => "http://img.com/1.png", "image_width" => 100, "image_height" => 100, "alt_text" => "img" }
        ]
      }
      result = JSON.parse(subject.send(:process_blocks, data))
      blocks = result["blocks"]
      image_blocks = blocks.select { |b| b.is_a?(Hash) && b.dig("attrs", "url") == "http://img.com/1.png" }
      expect(image_blocks.size).to eq(1)
    end

    it "includes no extra blocks for a section block" do
      data = {
        "text" => "hello",
        "blocks" => [
          { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "section text" } }
        ]
      }
      result = JSON.parse(subject.send(:process_blocks, data))
      blocks = result["blocks"]
      image_blocks = blocks.select { |b| b.is_a?(Hash) && b["type"] == "ImageBlock" }
      expect(image_blocks.size).to eq(0)
    end
  end
end
