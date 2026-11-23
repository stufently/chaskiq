# frozen_string_literal: true

module Types
  module AppTypeDirectoryResolvers
    def app_user(id:)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_users?, with: AppPolicy

      app_user = object.app_users.find(id)
      app_user.log_async(
        action: "profile_viewed",
        user: current_user,
        ip: context[:request].remote_ip
      )
      app_user
    end

    def agents
      authorize! object, to: :show?, with: AppPolicy
      object.agents.with_attached_avatar.where(invitation_token: nil)
    end

    def role_agents
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_team?, with: AppPolicy
      object.roles
    end

    def not_confirmed_agents
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_team?, with: AppPolicy

      object.agents.invitation_not_accepted
    end

    def agent(id:)
      authorize! object, to: :show?, with: AppPolicy
      object.agents.find(id)
    end

    def contact_search(term:)
      if Chaskiq::Config.get("SEARCHKICK_ENABLED") == "true" && object.searchkick_enabled?
        AppUser.search(
          term,
          fields: %i[name last_name first_name email phone],
          where: { app_id: object.id }
        )
      else
        query_term = :last_name_or_first_name_or_name_or_email_or_phone_i_cont_any
        @collection = object.app_users.limit(10).ransack(
          query_term => term
        ).result
      end
    end

    def contact_search_by_profile(provider:, profile_id:)
      authorize! object, to: :can_manage_users?, with: AppPolicy
      object.external_profiles.find_by(provider: provider, profile_id: profile_id)
    end

    def agent_search(term:)
      query_term = :last_name_or_first_name_or_name_or_email_i_cont_any
      @collection = object.agents.humans.limit(10).ransack(
        query_term => term
      ).result
    end

    def available_roles
      PermissionsService.list
    end

    def current_app_role
      current_user
      role = object.roles.find_by(agent_id: current_user.id)
      {
        name: role.role,
        owner: object.owner_id == current_user.id,
        definition: PermissionsService.list[role.role]
      }
    end

    def segments
      # object.plan.allow_feature!('Segments')
      # authorize! object, to: :show?, with: AppPolicy
      # authorize! object, to: :can_read_segments?, with: AppPolicy

      Segment.union_scope(
        object.segments.all, Segment.where(app_id: nil)
      ).order(:id)
    end

    def segment(id:)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_segments?, with: AppPolicy

      s = Segment.where("app_id is null ").where(id: id).first
      s.presence || object.segments.find(id)
    end
  end
end
