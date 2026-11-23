# frozen_string_literal: true

module Types
  module AppTypeReportResolvers
    def dashboard(range:, kind:, package: nil)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_reports?, with: AppPolicy

      if package.present?
        return AppPackageDashboard.new(
          app: object,
          range: range,
          package: package
        ).report_for(kind)
      end

      whitelist = %w[
        visits
        browser_name
        browser
        lead_os
        user_os
        user_country
        first_response_time
        incoming_messages
        outgoing_messages
        opened_conversations
        solved_conversations
        resolution_avg
        app_package
        app_packages
        app_packages_list
      ]
      raise "no dashboard available at this address" unless whitelist.include?(kind)

      Dashboard.new(
        app: object,
        range: range,
        package: package
      ).send(kind)
    end

    def app_packages_dashboard
      AppPackageDashboard.app_packages_list(object)
    end

    def app_package_dashboard(package:)
      authorize! object, to: :can_read_reports?, with: AppPolicy

      integration = AppPackageDashboard.app_package(object, package)
      {
        name: integration.app_package.name,
        icon: integration.app_package.icon,
        paths: integration.message_api_klass.try(:report_kinds) || []
      }
    end
  end
end
