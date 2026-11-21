# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::MessengerType do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }

  before { app.update!(privacy_consent_required: "eu") }

  def needs_privacy_consent(location)
    context = { set_locale: -> {}, get_app_user: -> { user }, request: double(location: location) }
    described_class.send(:new, app, context).needs_privacy_consent
  end

  it "requires consent for a user in an EU country" do
    expect(needs_privacy_consent(double(country_code: "DE"))).to be(true)
  end

  it "does not require consent for a user outside the EU" do
    expect(needs_privacy_consent(double(country_code: "US"))).to be(false)
  end

  it "does not require consent when the location is unknown" do
    expect(needs_privacy_consent(nil)).to be(false)
  end
end
