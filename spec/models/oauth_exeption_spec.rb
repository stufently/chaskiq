# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthExeption do
  it "has StandardError as superclass" do
    expect(OauthExeption.superclass).to eq(StandardError)
  end

  it "defaults message and exception_type" do
    e = OauthExeption.new
    expect(e.message).to eq("This is a custom exception")
    expect(e.instance_variable_get(:@exception_type)).to eq("custom")
  end

  it "accepts custom message and exception_type" do
    e = OauthExeption.new("Oauth Exception!", "oauth")
    expect(e.message).to eq("Oauth Exception!")
    expect(e.instance_variable_get(:@exception_type)).to eq("oauth")
  end
end
