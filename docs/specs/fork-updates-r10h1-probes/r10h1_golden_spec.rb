# frozen_string_literal: true

# Golden generator of fork-updates-r10h1 (coordinator's probe, never part of the suite). Runs every
# case of $R10H_CASES (r10h1_cases.json) through MessageApis::ContentShowcase::Presenter and writes
# the cases with their "outcome" to $R10H_GOLDEN_OUT as JSON.pretty_generate + "\n". r10h1_tests.rb
# runs it against BASE's code: the committed fixture must be exactly that output.
# outcome = canonical form of the returned value (symbol keys/values as ":name", parameters as
# {"@parameters" => to_unsafe_h}) or {"@raise" => class name} when the hook raises.
require "rails_helper"

RSpec.describe "r10h1 golden generator" do
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

  it "writes the golden fixture" do
    cases = JSON.parse(File.read(ENV.fetch("R10H_CASES")))
    golden = cases.map do |c|
      stub_link_cards(c["link_cards"])
      ctx = ActionController::Parameters.new(c["ctx"])
      c.merge("outcome" => outcome { described_class_hook(c["hook"], c["kind"], ctx) })
    end
    File.write(ENV.fetch("R10H_GOLDEN_OUT"), "#{JSON.pretty_generate(golden)}\n")
    expect(golden.size).to eq(cases.size)
  end

  def described_class_hook(hook, kind, ctx)
    MessageApis::ContentShowcase::Presenter.public_send("#{hook}_hook", kind: kind, ctx: ctx)
  end
end
