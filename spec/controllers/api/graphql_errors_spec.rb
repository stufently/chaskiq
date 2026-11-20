# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  describe "non-StandardError exception handling" do
    it "does not rescue non-StandardError exceptions" do
      non_standard = Class.new(Exception)
      allow(ChaskiqSchema).to receive(:execute).and_raise(non_standard)

      request.headers["HTTP_APP"] = "nonexistent"
      expect {
        post :execute, params: { query: "{ app { key } }" }, as: :json
      }.to raise_error(non_standard)
    end
  end
end
