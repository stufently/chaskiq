# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Article types ordering", type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }

  describe "Types::ArticleSettingsType#collections" do
    it "returns collections ordered by position ascending, not id" do
      # Create collections — acts_as_list assigns positions 1, 2
      app.article_collections.create!(title: "first")
      app.article_collections.create!(title: "second")
      article_setting = ArticleSetting.create!(app: app, subdomain: "test")

      # Reverse positions so order by position differs from order by id
      collections = app.article_collections.order(:id).to_a
      collections[0].update_column(:position, 2)
      collections[1].update_column(:position, 1)

      context = { current_user: agent }
      settings_type = Types::ArticleSettingsType.send(:new, article_setting, context)
      allow(settings_type).to receive(:authorize!).and_return(true)

      result = settings_type.collections
      titles = result.map(&:title)
      # Should be ordered by position (reversed), not by id
      expect(titles).to eq(%w[second first])

      # Verify positions are used for ordering
      positions = result.map(&:position)
      expect(positions).to eq(positions.sort)
    end
  end

  describe "Types::ArticleType#prev_article_url" do
    let(:collection) { app.article_collections.create!(title: "Test Collection") }

    it "returns nil for the only published article" do
      article = Article.create!(
        app: app,
        author: agent,
        collection: collection,
        title: "Only Article",
        state: "published",
        position: 1
      )

      context = { current_user: agent }
      article_type = Types::ArticleType.send(:new, article, context)

      expect(article_type.prev_article_url).to be_nil
    end

    it "returns the previous article when position > 1" do
      article1 = Article.create!(
        app: app,
        author: agent,
        collection: collection,
        title: "First Article",
        state: "published",
        position: 1
      )
      article3 = Article.create!(
        app: app,
        author: agent,
        collection: collection,
        title: "Third Article",
        state: "published",
        position: 3
      )

      context = { current_user: agent }
      article_type = Types::ArticleType.send(:new, article3, context)

      result = article_type.prev_article_url
      expect(result).to eq(article1)
    end
  end
end
