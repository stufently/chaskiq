# frozen_string_literal: true

require "rails_helper"

RSpec.describe OriginValidator do
  let(:host) { "http://loc.cl:3002" }

  describe "#is_valid?" do
    it "returns true when app is nil" do
      expect(described_class.new(app: nil, host: host).is_valid?).to eq(true)
    end

    it "returns true when app is wildcard" do
      expect(described_class.new(app: "*", host: host).is_valid?).to eq(true)
    end

    it "returns true when host matches one of multiple domains" do
      expect(described_class.new(app: "http://other.io, http://loc.cl:3002", host: host).is_valid?).to eq(true)
    end

    it "raises NonAcceptedOrigin when domain does not match" do
      expect { described_class.new(app: "http://loc.cl", host: host).is_valid? }
        .to raise_error(OriginValidator::NonAcceptedOrigin)
    end
  end

  describe "#validate_domain" do
    it "returns true for matching domain with port" do
      expect(described_class.new(app: nil, host: host).validate_domain("http://loc.cl:3002")).to eq(true)
    end

    it "returns false for domain without port" do
      expect(described_class.new(app: nil, host: host).validate_domain("http://loc.cl")).to eq(false)
    end

    it "returns false for different scheme" do
      expect(described_class.new(app: nil, host: host).validate_domain("https://loc.cl:3002")).to eq(false)
    end
  end

  describe "renamed" do
    describe "#valid?" do
      it "returns true when app is nil" do
        expect(described_class.new(app: nil, host: host).valid?).to eq(true)
      end

      it "returns true when app is wildcard" do
        expect(described_class.new(app: "*", host: host).valid?).to eq(true)
      end

      it "returns true when host matches one of multiple domains" do
        expect(described_class.new(app: "http://other.io, http://loc.cl:3002", host: host).valid?).to eq(true)
      end

      it "raises NonAcceptedOrigin when domain does not match" do
        expect { described_class.new(app: "http://loc.cl", host: host).valid? }
          .to raise_error(OriginValidator::NonAcceptedOrigin)
      end
    end

    describe "#validate_domain?" do
      it "returns true for matching domain with port" do
        expect(described_class.new(app: nil, host: host).validate_domain?("http://loc.cl:3002")).to eq(true)
      end

      it "returns false for domain without port" do
        expect(described_class.new(app: nil, host: host).validate_domain?("http://loc.cl")).to eq(false)
      end

      it "returns false for different scheme" do
        expect(described_class.new(app: nil, host: host).validate_domain?("https://loc.cl:3002")).to eq(false)
      end
    end
  end
end
