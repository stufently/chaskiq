# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppPackageIntegration do
  describe "#get_presenter_manager" do
    it "returns the Calendly presenter for a Calendly package" do
      integration = described_class.new(app_package: AppPackage.new(name: "Calendly"))
      expect(integration.get_presenter_manager).to eq(MessageApis::Calendly::Presenter)
    end

    it "returns ExternalPresenterManager for an unknown package" do
      integration = described_class.new(app_package: AppPackage.new(name: "NoSuchPackage"))
      expect(integration.get_presenter_manager).to eq(ExternalPresenterManager)
    end
  end
end
