# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AppType do
  let(:app) { FactoryBot.create(:app) }
  let(:instance) { described_class.send(:new, app, {}) }

  before do
    allow(instance).to receive(:authorize!).and_return(true)
  end

  describe "#app_packages_capabilities" do
    it "raises for an unknown kind" do
      expect { instance.app_packages_capabilities(kind: "nope") }
        .to raise_error(RuntimeError, "not in type")
    end

    it "returns empty for a valid kind with no integrations" do
      result = instance.app_packages_capabilities(kind: "inbox")
      expect(result).to be_empty
    end
  end

  describe "#articles" do
    let(:plan) { double("plan") }
    let(:all_articles) { double("all_articles") }
    let(:published_scope) { double("published", page: double(per: "published_result")) }
    let(:draft_scope) { double("draft", page: double(per: "draft_result")) }
    let(:all_scope) { double("all_scope") }

    before do
      allow(app).to receive(:plan).and_return(plan)
      allow(plan).to receive(:allow_feature!).and_return(true)
      allow(all_articles).to receive(:published).and_return(published_scope)
      allow(all_articles).to receive(:draft).and_return(draft_scope)
      allow(all_articles).to receive(:page).and_return(all_scope)
      allow(all_scope).to receive(:per).and_return("all_result")
    end

    it "returns all articles for mode 'all'" do
      allow(app).to receive(:articles).and_return(all_articles)
      result = instance.articles(page: 1, per: 6, lang: "en", mode: "all", search: nil)
      expect(result).to eq("all_result")
    end

    it "returns published articles for mode 'published'" do
      allow(app).to receive(:articles).and_return(all_articles)
      result = instance.articles(page: 1, per: 6, lang: "en", mode: "published", search: nil)
      expect(result).to eq("published_result")
    end

    it "returns draft articles for mode 'draft'" do
      allow(app).to receive(:articles).and_return(all_articles)
      result = instance.articles(page: 1, per: 6, lang: "en", mode: "draft", search: nil)
      expect(result).to eq("draft_result")
    end

    it "raises NoMethodError for an unknown mode" do
      allow(app).to receive(:articles).and_return(all_articles)
      expect { instance.articles(page: 1, per: 6, lang: "en", mode: "unknown", search: nil) }
        .to raise_error(NoMethodError)
    end
  end

  describe "#plans" do
    it "returns nil when payment_service is nil" do
      allow(app).to receive(:payment_service).and_return(nil)
      expect(instance.plans).to be_nil
    end

    it "returns plans sorted by pricing when service provides them" do
      svc = double("service")
      plans_data = [{ pricing: 30 }, { pricing: 10 }, { pricing: 20 }]
      allow(app).to receive(:payment_service).and_return(double(new: svc))
      allow(svc).to receive(:get_plans).and_return(plans_data)
      result = instance.plans
      expect(result.pluck(:pricing)).to eq([10, 20, 30])
    end

    it "returns nil when get_plans returns nil" do
      svc = double("service")
      allow(app).to receive(:payment_service).and_return(double(new: svc))
      allow(svc).to receive(:get_plans).and_return(nil)
      expect(instance.plans).to be_nil
    end
  end
end
