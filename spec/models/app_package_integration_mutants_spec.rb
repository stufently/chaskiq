# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppPackageIntegration do
  it "uses the built-in Calendly presenter and classifies the integration as internal" do
    integration = described_class.new(app_package: AppPackage.new(name: "Calendly"))

    expect(integration.presenter).to eq(MessageApis::Calendly::Presenter)
    expect(integration).not_to be_external_package
  end
end
