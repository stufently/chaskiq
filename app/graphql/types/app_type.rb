# frozen_string_literal: true

module Types
  class AppType < Types::PublicAppType
    include AppTypeConversationResolvers
    include AppTypeHelpCenterResolvers
    include AppTypeIntegrationResolvers
    include AppTypeReportResolvers
    include AppTypeDirectoryResolvers

    field :state, String, null: true
    field :timezone, String, null: true
    field :config_fields, Types::JsonType, null: true
    field :preferences, Types::JsonType, null: true
    field :app_users, [Types::AppUserType], null: true
    field :team_schedule, Types::JsonType, null: true
    field :gather_social_data, Boolean, null: true
    field :register_visits, Boolean, null: true
    field :allow_idle_sessions, Boolean, null: true
    field :translations, [Types::JsonType], null: true
    field :custom_fields, [Types::JsonType], null: true
    field :app_packages, [Types::AppPackageType], null: true
    field :agent_app_packages, [Types::AppPackageType], null: true
    field :editor_app_packages, [Types::AppPackageType], null: true
    field :follow_action_app_packages, [Types::AppPackageType], null: true
    field :tag_list, [Types::JsonType], null: true
    field :user_home_apps, [Types::JsonType], null: true
    field :inbox_apps, [Types::JsonType], null: true
    field :visitor_home_apps, [Types::JsonType], null: true
    field :plans, [Types::JsonType], null: true
    field :plan, Types::JsonType, null: true
    field :inbound_email_address, String, null: true
    field :outgoing_email_domain, String, null: true
    field :sorted_agents, [String], null: true

    field :team, Types::TeamType, null: true do
      argument :id, String, required: false
    end

    def team(id:)
      object.teams.find(id)
    end

    field :teams, Types::PaginatedTeamsType, null: true do
      argument :page, Integer, required: false, default_value: 1
      argument :per, Integer, required: false, default_value: 20
      argument :sort, String, required: false
    end

    def teams(per:, page:, sort: nil)
      object.teams.page(page).per(per)
    end

    def allow_idle_sessions
      Chaskiq::Config.get("ALLOW_IDLE_SESSIONS")
    end

    def plan
      return { disabled: true } unless context[:enabled_subscriptions]

      object.plan
    end

    def inbox_apps
      object.inbox_apps.presence || object.default_home_apps
    end

    def plans
      service = object.payment_service&.new
      service&.get_plans&.sort_by { |p| p[:pricing] }
    end

    field :user_transactions, [Types::JsonType], null: true
    def user_transactions
      object.payment_service.new.get_user_transactions(
        object.payment_attribute("user_id")
      )
    end

    field :subscription_transactions, [Types::JsonType], null: true
    def subscription_transactions
      object.payment_service.new.get_subscription_transactions(object)
      # rescue StandardError
      #  []
    end

    field :subscription_details, Types::JsonType, null: true
    def subscription_details
      if (sub_id = object.payment_attribute("subscription_id")) && sub_id
        object.payment_service.new.get_subscription(
          object.payment_attribute("subscription_id")
        )
      else
        {}
      end
    end

    field :update_subscription_plan, Types::JsonType, null: true do
      argument :plan_id, Integer, required: true
    end

    def update_subscription_plan(plan_id:)
      object.payment_service.new.update_subscription(
        object.paddle_subscription_id,
        plan_id: plan_id,
        passthrough: object.key
      )
    end

    field :subscriptions_enabled, Boolean, null: true
    def subscriptions_enabled
      context[:enabled_subscriptions]
    end

    field :available_roles, Types::JsonType, null: true
    field :current_app_role, Types::JsonType, null: true
    def tag_list
      authorize! object, to: :show?, with: AppPolicy
      object.tag_list || []
    end

    field :event_types, [Types::JsonType], null: true
    field :outgoing_webhooks, [Types::JsonType], null: true

    def outgoing_webhooks
      object.plan.allow_feature!("OutgoingWebhooks")
      authorize! object, to: :can_read_outgoing_webhooks?, with: AppPolicy
      object.outgoing_webhooks
    end

    def event_types
      Event::EVENT_CONSTANTS
    end

    field :agent_app_package, Types::AppPackageType, null: true do
      argument :id, String, required: true, default_value: ""
    end

    field :app_packages_capabilities, [Types::AppPackageIntegrationType], null: true do
      argument :kind, String, required: true, default_value: ""
    end

    def gather_social_data
      authorize! object, to: :show?, with: AppPolicy
      ActiveModel::Type::Boolean.new.cast(object.gather_social_data)
    end

    def register_visits
      authorize! object, to: :show?, with: AppPolicy
      ActiveModel::Type::Boolean.new.cast(object.register_visits)
    end

    field :app_package_integrations, [Types::AppPackageIntegrationType], null: true

    field :encryption_key, String, null: true

    def encryption_key
      # authorize! object, to: :manage?, with: AppPolicy
      object.encryption_key unless context[:from_api]
    end

    field :conversations, Types::PaginatedConversationsType, null: true do
      argument :page, Integer, required: false, default_value: 1
      argument :per, Integer, required: false, default_value: 20
      argument :sort, String, required: false
      argument :filter, String, required: false
      argument :agent_id, String, required: false
      argument :tag, String, required: false
      argument :term, String, required: false
      argument :channel_id, String, required: false
    end

    field :conversations_counts, Types::JsonType, null: true

    field :conversations_tag_counts, Types::JsonType, null: true

    field :conversations_channels_counts, Types::JsonType, null: true

    field :conversation, Types::ConversationType, null: true do
      argument :id, String, required: false
    end

    field :app_user, Types::AppUserType, null: true do
      argument :id, String, required: false
    end

    field :campaigns, Types::PaginatedCampaignType, null: true do
      argument :mode, String, required: false
    end

    def campaigns(mode:)
      # object.plan.allow_feature!(mode.classify.pluralize)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_campaigns?, with: AppPolicy

      collection = object.send(mode) if Message.allowed_types.include?(mode)
      collection.page(1).per(20)
    end

    field :campaign, Types::CampaignType, null: true do
      argument :mode, String, required: false
      argument :id, String, required: false
    end

    def campaign(mode:, id:)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_campaigns?, with: AppPolicy

      collection = object.send(mode) if Message.allowed_types.include?(mode)
      collection.find(id)
    end

    field :agents, [Types::AgentType], null: false

    field :role_agents, [Types::RoleType], null: false

    field :not_confirmed_agents, [Types::AgentType], null: false

    field :agent, Types::AgentType, null: false do
      argument :id, String, required: true
    end

    field :segments, [Types::SegmentType], null: true

    field :segment, Types::SegmentType, null: true do
      argument :id, String, required: true
    end

    field :assignment_rules, [Types::AssignmentRuleType], null: true

    def assignment_rules
      # object.plan.allow_feature!('AssignmentRules')
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_assignment_rules?, with: AppPolicy

      object.assignment_rules.order(:priority)
    end

    field :quick_replies, [Types::QuickReplyType], null: true do
      argument :lang, String, required: false, default_value: I18n.default_locale
      argument :q, String, required: false, default_value: nil
    end

    def quick_replies(lang:, q:)
      I18n.locale = lang
      authorize! object, to: :can_read_quick_replies?, with: AppPolicy
      if q.present?
        return object.quick_replies
                     .ransack(title_cont: q)
                     .result(distinct: true)
      end

      object.quick_replies
    end

    field :quick_reply, Types::QuickReplyType, null: true do
      argument :id, String, required: true
      argument :lang, String, required: false, default_value: I18n.default_locale
    end

    def quick_reply(id:, lang:)
      I18n.locale = lang
      authorize! object, to: :can_read_quick_replies?, with: AppPolicy
      object.quick_replies.find(id)
    end

    field :articles, Types::PaginatedArticlesType, null: true do
      argument :page, Integer, required: true
      argument :per, Integer, required: false, default_value: 6
      argument :lang, String, required: false, default_value: I18n.default_locale
      argument :mode, String, required: false, default_value: "all"
      argument :search, String, required: false, default_value: nil
    end

    field :articles_uncategorized, Types::PaginatedArticlesType, null: true do
      argument :page, Integer, required: true
      argument :per, Integer, required: false, default_value: 20
      argument :lang, String, required: false, default_value: I18n.default_locale
    end

    field :article_settings, Types::ArticleSettingsType, null: true
    field :article, Types::ArticleType, null: true do
      argument :id, String, required: true
      argument :lang, String, required: false, default_value: I18n.default_locale.to_s
    end

    field :contact_search, [Types::AppUserType], null: true do
      argument :term, String, required: true, default_value: ""
    end

    field :contact_search_by_profile, Types::ExternalProfileType, null: true do
      argument :provider, String, required: true, default_value: ""
      argument :profile_id, String, required: true, default_value: ""
    end

    field :agent_search, [Types::AgentType], null: true do
      argument :term, String, required: true, default_value: ""
    end

    field :collections, [Types::CollectionType], null: true do
      argument :lang, String, required: false, default_value: I18n.default_locale.to_s
    end

    field :collection, Types::CollectionType, null: true do
      argument :id, String, required: true
      argument :lang, String, required: false, default_value: I18n.default_locale.to_s
    end

    field :bot_tasks, Types::PaginatedBotTasksType, null: false do
      argument :lang, String, required: false, default_value: I18n.default_locale.to_s
      argument :mode, String, required: false, default_value: "outbound"
      argument :filters, Types::BotTaskFilterType, required: false, default_value: {}
      argument :page, Integer, required: false, default_value: 1
    end

    def bot_tasks(lang:, mode:, filters:, page:)
      # object.plan.allow_feature!('BotTasks')
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_routing_bots?, with: AppPolicy

      object.bot_tasks

      collection = object.bot_tasks.for_new_conversations if mode == "new_conversations"

      collection = object.bot_tasks.for_outbound if mode == "outbound"

      collection = collection.where(state: filters["state"]) if filters["state"].present?

      handle_bot_tasks_filters(filters, collection).ordered
                                                   .page(page)
                                                   .per(12)
    end

    field :bot_task, Types::BotTaskType, null: true do
      argument :id, String, required: true
      argument :lang, String, required: false, default_value: I18n.default_locale.to_s
    end

    def bot_task(id:, lang:)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_routing_bots?, with: AppPolicy
      object.bot_tasks.find(id)
    end

    field :dashboard, Types::JsonType, null: true do
      argument :range, Types::AnyType, required: true
      argument :kind,  String, required: true
      argument :package, String, required: false
    end

    field :app_packages_dashboard, Types::JsonType, null: true do
      argument :package, String, required: false
    end

    field :app_package_dashboard, Types::JsonType, null: true do
      argument :package, String, required: false
    end

    # OAUTH
    field :oauth_applications, [OauthApplicationType], null: true
    def oauth_applications
      object.plan.allow_feature!("OauthApplications")
      # authorize! object, to: :manage?, with: AppPolicy
      authorize! object, to: :can_read_oauth_applications?, with: AppPolicy
      object.oauth_applications.ordered_by(:created_at)
    end

    field :oauth_application, OauthApplicationType, null: true do
      argument :uid, String, required: false
    end

    def oauth_application(uid:)
      # authorize! object, to: :manage?, with: AppPolicy
      authorize! object, to: :can_read_oauth_applications?, with: AppPolicy
      object.oauth_applications.find_by(uid: uid)
    end

    field :authorized_oauth_applications, [OauthApplicationType], null: true
    def authorized_oauth_applications
      # authorize! object, to: :manage?, with: AppPolicy
      authorize! object, to: :can_read_oauth_applications?, with: AppPolicy
      object.oauth_applications.authorized_for(current_user)
    end

    field :agent_editor_settings, AnyType, null: true
    field :user_editor_settings, AnyType, null: true
    field :lead_editor_settings, AnyType, null: true

    private

    def handle_bot_tasks_filters(filters, collection)
      return collection if filters["users"].blank?

      ors = nil
      filters["users"].each_with_index do |filter, _index|
        ors = ors.nil? ? BotTask.infix([filter]) : ors.or(BotTask.infix([filter]))
      end
      collection.where(ors) if ors.present?
    end
  end
end
