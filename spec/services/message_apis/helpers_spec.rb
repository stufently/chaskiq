# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Helpers do
  let(:helper_class) do
    Class.new do
      include MessageApis::Helpers
      def self.name; "TestHelper"; end
    end
  end
  let(:helper) { helper_class.new }

  describe "#keygen" do
    it "generates a string of 8 lowercase letters" do
      50.times do
        result = helper.keygen
        expect(result).to match(/\A[a-z]{8}\z/)
      end
    end

    it "uses letters beyond m over many samples" do
      letters = 200.times.map { helper.keygen }.join.chars.uniq
      expect(letters & ("n".."z").to_a).not_to be_empty
    end
  end

  describe "#main_doc" do
    it "returns a hash with type doc" do
      result = helper.main_doc([{ type: "text", text: "hello" }])
      expect(result[:type]).to eq("doc")
    end

    it "has a content key with the blocks array" do
      blocks = [{ type: "text", text: "hello" }]
      result = helper.main_doc(blocks)
      expect(result[:content]).to eq(blocks)
    end
  end

  describe "#serialized_block" do
    it "returns a hash with type text" do
      result = helper.serialized_block("hello")
      expect(result[:type]).to eq("text")
    end

    it "includes the text content" do
      result = helper.serialized_block("hello world")
      expect(result[:text]).to eq("hello world")
    end
  end
end
