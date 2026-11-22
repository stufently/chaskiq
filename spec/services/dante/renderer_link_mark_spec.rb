# frozen_string_literal: true

require "nokogiri"
require "rails_helper"

RSpec.describe Dante::Renderer, "link mark" do
  let(:raw) do
    {
      content: [
        {
          type: "paragraph",
          content: [
            {
              type: "text",
              text: "site",
              marks: [
                { type: "link", attrs: { href: "https://example.com", target: "_blank" } }
              ]
            }
          ]
        }
      ]
    }
  end

  let(:html) { Dante::Renderer.new(raw: raw, domain: "example.com").render }
  let(:anchor) { Nokogiri::HTML.fragment(html).at_css("a") }

  it "renders the <a> with exact attributes" do
    expected = {
      "class" => "graf markup--anchor markup--anchor-readOnly",
      "href" => "https://example.com",
      "target" => "_blank",
      "rel" => "noopener noreferrer nofollow"
    }
    expect(anchor.to_h).to eq(expected)
  end

  it "renders the text content" do
    expect(anchor.text).to eq("site")
  end
end
