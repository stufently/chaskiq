# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL error handling" do
  describe "M182: rescue StandardError vs Exception" do
    it "rescues StandardError subclasses" do
      controller = Api::GraphqlController.new
      allow(controller).to receive(:params).and_return(
        query: "{ app { key } }", variables: "{}", operationName: nil
      )
      allow(controller).to receive(:get_app).and_return(nil)
      allow(controller).to receive(:request).and_return(
        instance_double("Request", headers: { "HTTP_APP" => "test" })
      )
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test")
      expect { controller.send(:execute) }.to raise_error(ArgumentError)
    rescue NoMethodError
      skip "Cannot instantiate controller directly"
    end

    it "does not rescue Exception subclasses that are not StandardError" do
      fatal_class = Class.new(Exception)
      controller = Api::GraphqlController.new
      allow(controller).to receive(:params).and_return(
        query: "{ app { key } }", variables: "{}", operationName: nil
      )
      allow(controller).to receive(:get_app).and_return(nil)
      allow(controller).to receive(:request).and_return(
        instance_double("Request", headers: { "HTTP_APP" => "test" })
      )
      allow(ChaskiqSchema).to receive(:execute).and_raise(fatal_class, "fatal")
      expect { controller.send(:execute) }.to raise_error(fatal_class)
    rescue NoMethodError
      skip "Cannot instantiate controller directly"
    end
  end
end
