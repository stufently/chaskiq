# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TelnyxSms API" do
  let(:source) { Rails.root.join("app/services/message_apis/telnyx_sms/api.rb").read }

  describe "MAX_MEDIA_BYTES (M146)" do
    it "is 5MB not 1KB" do
      expect(source).to match(/MAX_MEDIA_BYTES\s*=\s*5\s*\*\s*1024\s*\*\s*1024/)
    end
  end

  describe "inbound_blocks empty line rejection (M155)" do
    it "rejects empty lines" do
      expect(source).to match(/split.*reject\(&:empty\?\)/)
    end
  end

  describe "send_sms_message phone normalization (N05/N06)" do
    it "strips + with delete('+')" do
      expect(source).to match(/channel_id\.delete\("\+"\)/)
    end

    it "adds + prefix in the to field" do
      expect(source).to match(/to:\s*"\+#\{channel_id\}"/)
    end
  end
end
