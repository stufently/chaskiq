# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::MessengerType do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }

  def needs_privacy_consent(setting, location, consented: false)
    app.update!(privacy_consent_required: setting)
    user.update!(privacy_consent: true) if consented
    context = { set_locale: -> {}, get_app_user: -> { user }, request: double(location: location) }
    described_class.send(:new, app, context).needs_privacy_consent
  end

  describe "EuCountries list mutant-killing" do
    it "X13: includes GB in the EU country list" do
      expect(EuCountries.includes?("GB")).to be(true)
    end

    it "X14: includes FR in the EU country list" do
      expect(EuCountries.includes?("FR")).to be(true)
    end

    it "X15: does not include NO or CH in the EU country list" do
      expect(EuCountries.includes?("NO")).to be(false)
      expect(EuCountries.includes?("CH")).to be(false)
    end
  end

  describe "needs_privacy_consent mutant-killing" do
    it "X18: returns false when the user has already consented" do
      expect(needs_privacy_consent("eu", double(country_code: "DE"), consented: true)).to be(false)
    end

    it "X19: returns false (not nil) when the setting is none" do
      expect(needs_privacy_consent("none", double(country_code: "DE"))).to be(false)
    end

    it "X20: returns true when the setting is all" do
      expect(needs_privacy_consent("all", double(country_code: "US"))).to be(true)
    end

    it "X21: returns false (not nil) when the setting is empty" do
      expect(needs_privacy_consent("", double(country_code: "DE"))).to be(false)
    end
  end
end
