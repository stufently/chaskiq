# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiController do
  it "does not define EULocationError" do
    expect(described_class.const_defined?(:EULocationError, false)).to be(false)
  end
end
