# frozen_string_literal: true

class ExternalPresenterManager
  def self.post(url, data)
    # This it's just to restrict fields on app, refactor this!
    data[:ctx][:app] = data.dig(:ctx, :app).as_json(only: %i[key name])
    data[:ctx][:current_user] = data.dig(:ctx, :current_user).as_json(methods: %i[email kind display_name avatar_url])
    Rails.logger.debug url
    Rails.logger.debug data
    resp = Faraday.post(
      url,
      data.to_json,
      "Content-Type" => "application/json"
    )
    JSON.parse(resp.body)
  end

  def self.initialize_hook(data)
    url = data[:package].app_package.initialize_url
    post(url, data)
  end

  def self.configure_hook(data)
    url = data[:package].app_package.configure_url
    post(url, data)
  end

  def self.submit_hook(data)
    url = data[:package].app_package.submit_url
    post(url, data)
  end

  def self.sheet_hook(data)
    url = data[:package].app_package.sheet_url
    post(url, data)
  end

  def self.content_hook(data)
    url = data[:package].app_package.content_url
    post(url, data)
  end
end
