# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::ContentShowcase::Presenter do
  it "preserves article fields when autofill cannot get a preview" do
    url = "https://site.example.com/article"
    allow(MessageApis::SafeDownload).to receive(:fetch).with(url, max_bytes: 2 * 1024 * 1024).and_return(nil)
    context = ActionController::Parameters.new(
      field: { id: "autofill-0", action: { type: "submit" } },
      values: { article: [{ page_url: url, title: "Existing title", description: "Existing description" }] }
    )

    result = described_class.configure_hook(kind: "config", ctx: context)

    expect(result.fetch(:definitions)).to include(
      hash_including(name: "article[0][page_url]", value: url),
      hash_including(name: "article[0][title]", value: "Existing title"),
      hash_including(name: "article[0][description]", value: "Existing description")
    )
  end
end
