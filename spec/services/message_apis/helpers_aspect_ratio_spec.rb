# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Helpers do
  let(:helper) { Class.new { include MessageApis::Helpers }.new }

  it "scales down width larger than max" do
    expect(helper.get_aspect_ratio(2000.0, 500.0)).to eq(
      { width: 1000.0, height: 250.0, ratio: 25.0 }
    )
  end

  it "scales down height larger than max" do
    expect(helper.get_aspect_ratio(500.0, 2000.0)).to eq(
      { width: 250.0, height: 1000.0, ratio: 400.0 }
    )
  end

  it "does not scale when within max dimensions" do
    expect(helper.get_aspect_ratio(500.0, 900.0)).to eq(
      { width: 500.0, height: 900.0, ratio: 180.0 }
    )
  end

  it "uses integer division for integer inputs" do
    expect(helper.get_aspect_ratio(500, 400)).to eq(
      { width: 500, height: 400, ratio: 0 }
    )
  end
end
