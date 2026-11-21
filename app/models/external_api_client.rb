# frozen_string_literal: true

class ExternalApiClient
  attr_accessor :config
  attr_reader :api_url

  def initialize(config:)
    @config  = config
    @api_url = config["package"].app_package.api_url
  end

  def trigger(event)
    event.as_json

    payload = {
      action: event.action,
      created_at: event.created_at,
      data: {
        subject: subject_data(event.eventable),
        properties: event.properties
      }
    }

    post(@api_url, payload)
  end

  def report(path, options = {})
    # post(@api_url)
  end

  def enqueue_process_event(params, integration)
    params.merge!({ package: integration.as_json })
    post(@api_url, params)
  end

  def conn
    # site = Addressable::URI.parse(@api_url).site
    # @conn ||= Faraday.new(:url => site , request: { timeout: 2 } ) do |faraday|
    @conn ||= Faraday.new(request: { timeout: 2 }) do |faraday|
      faraday.request  :url_encoded
      faraday.response :logger
      faraday.adapter  Faraday.default_adapter
    end
  end

  def post(url, data)
    resp = conn.post(
      url,
      data.to_json,
      "Content-Type" => "application/json"
    )
    JSON.parse(resp.body)
  end

  def subject_data(eventable)
    case eventable.class
    when Conversation
      eventable.as_json(methods: %i[main_participant assignee latest_message]).to_json
    else
      eventable.to_json
    end
  end
end
