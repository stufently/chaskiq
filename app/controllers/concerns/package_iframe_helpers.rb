# frozen_string_literal: true

module PackageIframeHelpers
  extend ActiveSupport::Concern

  def handle_user_data(data)
    user_data = @app.decrypt(data["data"]["enc_data"])

    if user_data.present? && user_data[:email].present?
      @app.app_users.users.find_by(email: user_data[:email])
    else
      find_iframe_user(data)
    end
  rescue StandardError
    @app.app_users.find_by(
      session_id: cookies[cookie_namespace]
    )
  end

  def handle_url_data(url_base)
    if url_base.match(%r{^/package_iframe_internal/})
      "#{Chaskiq::Config.get('HOST')}#{url_base}"
    else
      url_base
    end
  end

  def iframe_package_request(url, data, app_user)
    resp = Faraday.post(url, data.merge!(user: app_user).to_json,
                        "Content-Type" => "application/json")
    resp.body
  end

  private

  def find_iframe_user(data)
    if data.dig("data", "enc_data", "identifier_key") && @app.compare_user_identifier(data["data"]["enc_data"])
      @app.app_users.users.find_by(email: data.dig("data", "enc_data", "email"))
    elsif data.dig("data", "session_id").present?
      @app.app_users.find_by(
        session_id: data.dig("data", "session_id")
      )
    else
      @app.app_users.find_by(
        session_id: cookies[cookie_namespace]
      )
    end
  end
end
