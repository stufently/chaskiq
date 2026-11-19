# frozen_string_literal: true

require "rails_helper"

RSpec.describe OembedController, type: :controller do
  it "returns a JSON preview error when the URL has no card" do
    url = "https://site.example.com/page"
    allow(MessageApis::SafeDownload).to receive(:fetch).with(url, max_bytes: 2 * 1024 * 1024).and_return(nil)

    get :show, params: { url: url }

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error_message" => "No preview available")
  end
end
