# frozen_string_literal: true

module Types
  module AppTypeHelpCenterResolvers
    def articles(page:, per:, lang:, mode:, search:)
      object.plan.allow_feature!("Articles")
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_help_center?, with: AppPolicy

      I18n.locale = lang
      case mode
      when "all"
        articles = object.articles
      when "published"
        articles = object.articles.published
      when "draft"
        articles = object.articles.draft
      end

      articles = object.articles.search(search) if search.present?

      articles.page(page).per(per)
    end

    def articles_uncategorized(page:, per:, lang:)
      # object.plan.allow_feature!('Articles')
      I18n.locale = lang
      authorize! object, to: :can_read_help_center?, with: AppPolicy
      object.articles.without_collection.page(page).per(per)
    end

    def article_settings
      authorize! object, to: :can_read_help_center?, with: AppPolicy
      # object.plan.allow_feature!('Articles')
      object.article_settings.presence || object.build_article_settings
    end

    def article(id:, lang:)
      object.plan.allow_feature!("Articles")
      I18n.locale = lang
      authorize! object, to: :can_read_help_center?, with: AppPolicy
      # authorize! object, to: :show?, with: AppPolicy
      object.articles.friendly.find(id)
    end

    def collections(lang:)
      object.plan.allow_feature!("Articles")
      I18n.locale = lang.to_sym
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_help_center?, with: AppPolicy
      object.article_collections.order(:position)
    end

    def collection(id:, lang:)
      authorize! object, to: :can_read_help_center?, with: AppPolicy
      # authorize! object, to: :show?, with: AppPolicy
      I18n.locale = lang.to_sym
      object.article_collections.friendly.find(id)
    end
  end
end
