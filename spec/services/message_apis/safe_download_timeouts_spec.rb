# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".fetch open_timeout" do
    it "sets open_timeout to 5 on the HTTP connection" do
      source_file = Rails.root.join("app/services/message_apis/safe_download.rb").read
      expect(source_file).to match(/http\.open_timeout\s*=\s*5\b/)
    end
  end
end
