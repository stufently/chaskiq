# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::ContentShowcase::Presenter, "hooks" do
  golden = JSON.parse(Rails.root.join("spec/fixtures/presenters/content_showcase_hooks.json").read)

  around do |example|
    I18n.with_locale(:en) { Time.use_zone("UTC") { example.run } }
  end

  def canon(obj)
    case obj
    when ActionController::Parameters then { "@parameters" => canon(obj.to_unsafe_h) }
    when Hash then obj.to_h { |k, v| [k.is_a?(Symbol) ? ":#{k}" : k.to_str, canon(v)] }
    when Array then obj.map { |v| canon(v) }
    when Symbol then ":#{obj}"
    when String, Integer, true, false, nil then obj
    else raise ArgumentError, "canon: #{obj.class}"
    end
  end

  def outcome
    result = yield
  rescue StandardError => e
    { "@raise" => e.class.name }
  else
    canon(result)
  end

  def stub_link_cards(cards)
    cards = cards.to_h do |url, card|
      [url, double("link card", title: card["title"], description: card["description"],
                                images: card["images"].map { |u| { url: u } })]
    end
    service = double("FetchLinkCardService")
    allow(service).to receive(:call) { |url| cards[url] }
    allow(FetchLinkCardService).to receive(:new).and_return(service)
  end

  golden.each do |c|
    it c["name"] do
      stub_link_cards(c["link_cards"])
      ctx = ActionController::Parameters.new(c["ctx"])
      result = outcome { described_class.public_send("#{c['hook']}_hook", kind: c["kind"], ctx: ctx) }
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(c["outcome"]))
    end
  end
end
