# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::MessengerType do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }

  def needs_privacy_consent(setting, location)
    app.update!(privacy_consent_required: setting)
    context = { set_locale: -> {}, get_app_user: -> { user }, request: double(location: location) }
    described_class.send(:new, app, context).needs_privacy_consent
  end

  it "requires consent for an EU country with the ue setting" do
    expect(needs_privacy_consent("ue", double(country_code: "DE"))).to be(true)
  end

  it "does not require consent outside the EU with the ue setting" do
    expect(needs_privacy_consent("ue", double(country_code: "US"))).to be(false)
  end

  it "does not require consent for an unknown location with the ue setting" do
    expect(needs_privacy_consent("ue", nil)).to be(false)
  end

  it "requires consent for an EU country with the eu setting" do
    expect(needs_privacy_consent("eu", double(country_code: "FR"))).to be(true)
  end
end
