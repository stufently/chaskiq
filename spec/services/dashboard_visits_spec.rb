# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard do
  let(:app) { FactoryBot.create(:app) }
  let(:range) { { from: "2023-11-01", to: "2023-11-30" } }

  after { AppIdentity.new(app.key).delete }

  it "returns recorded visits in the requested date range" do
    AppIdentity.new(app.key).visits.incr(1, Time.zone.at(1_700_000_040))

    expect(described_class.new(app: app, range: range).visits).to eq([{ day: "2023-11-14", value: 1 }])
  end

  it "returns no visits when the series has been deleted" do
    identity = AppIdentity.new(app.key)
    identity.visits.delete
    allow(AppIdentity).to receive(:new).with(app.key).and_return(identity)

    expect(described_class.new(app: app, range: range).visits).to eq([])
  end
end
