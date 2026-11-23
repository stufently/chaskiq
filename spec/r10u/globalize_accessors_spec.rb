# frozen_string_literal: true

require "rails_helper"

RSpec.describe GlobalizeAccessors do
  # Use Article which already includes GlobalizeAccessors
  describe ".globalize_accessors" do
    it "defines getter methods for each attribute and locale" do
      article = Article.new
      # Article has globalize_accessors for :description, :title
      expect(article).to respond_to(:title_en)
      expect(article).to respond_to(:description_en)
    end

    it "defines setter methods for each attribute and locale" do
      article = Article.new
      expect(article).to respond_to(:title_en=)
      expect(article).to respond_to(:description_en=)
    end

    it "sets globalize_locales class attribute" do
      expect(Article.globalize_locales).to eq(I18n.available_locales)
    end

    it "sets globalize_attribute_names class attribute" do
      expect(Article.globalize_attribute_names).to include(:title_en, :title_ru, :description_en, :description_ru)
    end
  end

  describe ".localized_attr_name_for" do
    it "returns attribute name with locale suffix" do
      expect(Article.localized_attr_name_for(:title, :en)).to eq("title_en")
      expect(Article.localized_attr_name_for(:title, :ru)).to eq("title_ru")
    end
  end

  describe "instance methods" do
    it "delegates localized_attr_name_for to class" do
      article = Article.new
      expect(article.localized_attr_name_for(:title, :en)).to eq("title_en")
    end
  end

  describe "getter behavior" do
    it "reads from globalize stash when present" do
      article = Article.new
      article.title_en = "English Title"
      expect(article.title_en).to eq("English Title")
    end

    it "returns nil or empty for unset attributes" do
      article = Article.new
      expect(article.title_en).to be_nil.or eq("")
    end
  end

  describe "setter behavior" do
    it "writes attribute value for locale" do
      article = Article.new
      article.title_en = "Test Title"
      expect(article.title_en).to eq("Test Title")
    end

    it "handles blank values" do
      article = Article.new
      article.title_en = ""
      expect(article.title_en).to be_blank
    end

    it "writes non-blank values to translation" do
      article = Article.new
      article.title_en = "New Title"
      expect(article.title_en).to eq("New Title")
    end
  end

  describe "multiple locales" do
    it "stores values independently for each locale" do
      article = Article.new
      article.title_en = "English"
      article.title_ru = "Русский"
      expect(article.title_en).to eq("English")
      expect(article.title_ru).to eq("Русский")
    end
  end

  describe "concern structure" do
    it "defines InstanceMethods module" do
      expect(described_class.const_defined?(:InstanceMethods)).to be true
    end

    it "provides class methods to including models" do
      expect(described_class.instance_methods).to be_empty
      expect(Article).to respond_to(:globalize_accessors)
      expect(Article).to respond_to(:localized_attr_name_for)
      expect(Article).to respond_to(:define_accessors)
      expect(Article).to respond_to(:define_getter)
      expect(Article).to respond_to(:define_setter)
      expect(Article).to respond_to(:each_attribute_and_locale)
    end
  end

  it "removes a persisted translation only after every translated attribute is blank" do
    app = FactoryBot.create(:app)
    author = app.add_agent({ email: "r10u-author@example.com" }).agent
    article = Article.create!(app: app, author: author, title_en: "Title", description_en: "Description", title_ru: "Title RU")

    article.reload.title_en = ""

    expect(Article.find(article.id).description_en).to eq("Description")
    expect(article.translations.where(locale: :en)).to exist

    article.description_en = ""

    expect(article.translations.where(locale: :en)).not_to exist
    expect(article.reload.title_ru).to eq("Title RU")
  end
end
