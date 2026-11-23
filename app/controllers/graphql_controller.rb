# frozen_string_literal: true

class GraphqlController < ApplicationController
  include HashEnsurer

  skip_before_action :verify_authenticity_token
  # before_action :doorkeeper_authorize!
  before_action :set_host_for_local_storage
  before_action :set_locale

  def execute
    render json: execute_request
  rescue OauthExeption
    render json: {
      error: {
        message: "token not valid"
      }, data: {}
    }, status: :unauthorized
  rescue ActiveRecord::RecordNotFound
    render json: {
      errors: [{
        message: "Data not found",
        data: {}
      }]
    }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.join("\n")
    json_error e.record
  rescue Plan::PlanError => e
    render json: {
      error: {
        message: JSON.parse(e.message)
      }, data: {}
    }, status: :payment_required
  # GraphQL::ExecutionError.new "Validation failed: #{error_messages}."
  rescue ActionPolicy::Unauthorized => e
    raise GraphQL::ExecutionError.new(
      # use result.message (backed by i18n) as an error message
      e.result.message,
      # use GraphQL error extensions to provide more context
      extensions: {
        code: :unauthorized,
        fullMessages: e.result.reasons.full_messages,
        details: e.result.reasons.details
      }
    )
  rescue StandardError => e
    # GraphQL::ExecutionError.new e.message
    # raise e unless Rails.env.development?
    handle_error_message e
  end

  private

  def execute_request
    variables = ensure_hash(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    rename_scout_transaction(operation_name)

    ChaskiqSchema.execute(
      query,
      variables: variables,
      context: build_context,
      operation_name: operation_name
    )
  end

  def build_context
    {
      current_user: current_user,
      request: request,
      doorkeeper_authorize: -> { api_authorize! },
      enabled_subscriptions: enabled_subscriptions?
    }
  end

  def rename_scout_transaction(operation_name)
    scout_transaction_name = "GraphQL/" + (operation_name || "unknown")
    ScoutApm::Transaction.rename(scout_transaction_name)
  end

  def api_authorize!
    # AUTH0
    if auth0_enabled?
      @auth0_resource ||= auth0_resource
      return @auth0_resource if @auth0_resource.present?
    end

    resource = current_resource_owner
    raise OauthExeption, "Oauth Exception!" unless resource

    # doorkeeper_authorize!
    resource
  end

  def set_host_for_local_storage
    ActiveStorage::Current.url_options = request.base_url if Rails.application.config.active_storage.service == :local
  end
end
