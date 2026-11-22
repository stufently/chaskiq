# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BlockManager, ".deliver_attachments" do
  let(:response) { double("successful response", success?: true) }

  def attachment(type, url)
    { "type" => type, "attrs" => { "url" => url } }
  end

  it "replays an attachment by its original index after an unusable URL" do
    invalid = attachment("ImageBlock", "")
    delivered = attachment("ImageBlock", "https://cdn.example.com/image.png")
    pending = attachment("FileBlock", "https://cdn.example.com/file.pdf")
    calls = []
    result = described_class.deliver_attachments(
      [invalid, delivered, pending],
      "caption",
      send_text: ->(text) { calls << text },
      already_sent: [1],
      on_success: ->(reply, index) { calls << [reply, index] }
    ) do |type, url, caption|
      calls << [type, url, caption]
      response
    end

    expect(calls).to eq([["FileBlock", "https://cdn.example.com/file.pdf", nil], [response, 2]])
    expect(result).to equal(response)
  end

  it "passes the original text index to the success hook" do
    invalid = attachment("ImageBlock", "")
    calls = []
    sender = lambda do |text|
      calls << text
      response
    end
    result = described_class.deliver_attachments(
      [invalid],
      "fallback",
      send_text: sender,
      already_sent: [],
      on_success: ->(reply, index) { calls << [reply, index] }
    ) { raise "unusable attachment reached the sender" }

    expect(calls).to eq(["fallback", [response, 1]])
    expect(result).to equal(response)
  end

  it "preserves LocalJumpError when a sendable attachment has no sender block" do
    image = attachment("ImageBlock", "https://cdn.example.com/image.png")

    expect do
      described_class.deliver_attachments([image], "", send_text: ->(_text) { response })
    end.to raise_error(LocalJumpError)
  end

  it "does not send text for a replayed fallback at the final index" do
    audio = attachment("AudioRecorderBlock", "https://cdn.example.com/voice.ogg")
    result = described_class.deliver_attachments(
      [audio],
      "caption",
      send_text: ->(_text) { raise "fallback was already sent" },
      captionless: %w[AudioRecorderBlock],
      already_sent: [1]
    ) { response }

    expect(result).to equal(response)
  end
end
