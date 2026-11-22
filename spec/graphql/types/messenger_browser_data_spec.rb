# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::MessengerType, "#browser_data" do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "browser@example.com", first_name: "Test") }

  let(:location) do
    double(
      city: "Santiago",
      region: "Santiago Metropolitan",
      country: nil,
      country_code: "CL",
      latitude: -33.4569,
      longitude: -70.6483,
      postal_code: "8320000",
      present?: true
    )
  end

  let(:request) do
    double(
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      accept_language: "es-CL,es;q=0.9",
      referrer: "https://google.com",
      remote_ip: "190.1.2.3",
      location: location
    )
  end

  let(:type) do
    described_class.send(:new, app, {
                           request: request,
                           get_app_user: -> { user },
                           set_locale: -> {}
                         })
  end

  before { type.enabled_for_user }

  it "returns the full browser data hash with location" do
    result = type.send(:browser_data)

    expect(result).to include(
      "name" => user.name,
      "email" => "browser@example.com"
    )
    expect(result).to include(
      referrer: "https://google.com",
      ip: "190.1.2.3",
      browser: "Chrome",
      browser_version: "120",
      os: :mac,
      os_version: "10.15.7",
      browser_language: "es"
    )
    expect(result).to include(
      city: "Santiago",
      region: "Santiago Metropolitan",
      country: COUNTRY_NAMES[:CL],
      country_code: "CL",
      lat: -33.4569,
      lng: -70.6483,
      postal: "8320000"
    )
  end

  context "without country name from location" do
    let(:location) do
      double(
        city: "Santiago",
        region: "Santiago Metropolitan",
        country: nil,
        country_code: "CL",
        latitude: -33.4569,
        longitude: -70.6483,
        postal_code: "8320000",
        present?: true
      )
    end

    it "falls back to COUNTRY_NAMES[:CL]" do
      result = type.send(:browser_data)
      expect(result[:country]).to eq(COUNTRY_NAMES[:CL])
    end
  end

  context "with location: nil" do
    let(:request) do
      double(
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        accept_language: "es-CL,es;q=0.9",
        referrer: "https://google.com",
        remote_ip: "190.1.2.3",
        location: nil
      )
    end

    it "does not include location keys" do
      result = type.send(:browser_data)
      expect(result).not_to have_key(:city)
      expect(result).not_to have_key(:region)
      expect(result).not_to have_key(:country)
      expect(result).not_to have_key(:country_code)
      expect(result).not_to have_key(:lat)
      expect(result).not_to have_key(:lng)
      expect(result).not_to have_key(:postal)
    end
  end
end
