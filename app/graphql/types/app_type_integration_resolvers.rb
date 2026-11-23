# frozen_string_literal: true

module Types
  module AppTypeIntegrationResolvers
    def editor_app_packages
      authorize! object, to: :show?, with: AppPolicy
      object.app_packages.tagged_with("editor")
            .joins(:app_package_integrations)
            .where.not(app_package_integrations: { id: nil }).uniq
    end

    def agent_app_package(id:)
      # object.app_package_integrations.find(id)
      # object.app_packages.find_by(name: id)
      current_user.app_packages.find(id)
    end

    def app_packages_capabilities(kind:)
      raise "not in type" unless %w[home conversations conversation_part bots inbox fixed_sidebar conversations_initiator].include?(kind)

      authorize! object, to: :show?, with: AppPolicy

      object.app_package_integrations
            .joins(:app_package)
            .where(
              app_package_id: object.app_packages.tagged_with(kind, on: "capabilities")
            ).order("app_packages.name desc")
    end

    def app_packages
      object.plan.allow_feature!("Integrations")
      authorize! object, to: :can_manage_app_packages?, with: AppPolicy

      integrations = object.app_package_integrations.map(&:app_package_id)

      app_packages = AppPackage.union_scope(
        AppPackage.enabled.where(agent_id: nil),
        AppPackage.published.enabled,
        AppPackage.enabled.where(agent_id: current_user.id)
      )

      app_packages = app_packages.where.not("id in(?)", integrations) if integrations.any?

      app_packages.order(:id).distinct
    end

    def agent_app_packages
      # authorize! object, to: :manage?, with: AppPolicy
      authorize! object, to: :can_manage_app_packages?, with: AppPolicy
      current_user.app_packages
    end

    def app_package_integrations
      object.plan.allow_feature!("Integrations")
      # authorize! object, to: :manage?, with: AppPolicy
      authorize! object, to: :can_manage_app_packages?, with: AppPolicy

      object.app_package_integrations
    end
  end
end
