# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RackBadRequest middleware order" do
  it "is installed in the middleware stack" do
    middleware_classes = Rails.application.middleware.map(&:name) || Rails.application.middleware.map { |m| m.respond_to?(:name) ? m.name : m.to_s }
    expect(middleware_classes).to include("Middleware::RackBadRequest")
  end

  it "sits before Rack::MethodOverride" do
    middleware_list = Rails.application.middleware.map { |m| m.respond_to?(:name) ? m.name : m.to_s }
    bad_request_idx = middleware_list.index("Middleware::RackBadRequest")
    method_override_idx = middleware_list.index("Rack::MethodOverride")
    expect(bad_request_idx).not_to be_nil
    expect(method_override_idx).not_to be_nil
    expect(bad_request_idx).to be < method_override_idx
  end
end
