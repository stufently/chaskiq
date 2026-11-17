# frozen_string_literal: true

# Probe for fork-updates-m1: package C (manual port of upstream PR #930 without the
# password complexity validation) and the ChaskiqBoot plugins-table guard from package B.
# Run: bash docs/specs/fork-updates-m1-probes/rspec_gate.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb
require_relative "../../../spec/rails_helper"

RSpec.describe "fork-updates-m1 runtime probe", type: :request do
  around do |example|
    previous = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = previous
  end

  # The frontend posts JSON (packages/store/src/actions/auth.ts): password grant to
  # /oauth/token.json, refresh_token grant to /oauth/token. Form posts are covered too.
  def statuses_for(path, ip, times, grant_type: "password", json: false)
    body = { grant_type: grant_type, email: "nobody-m1@example.com", password: "wrong-password",
             refresh_token: "not-a-real-refresh-token" }
    Array.new(times) do
      if json
        post path, params: body, env: { "REMOTE_ADDR" => ip }, as: :json
      else
        post path, params: body, env: { "REMOTE_ADDR" => ip }
      end
      response.status
    end
  end

  it "inserts Rack::Attack into the Rails middleware stack exactly once (railtie, not config.ru)" do
    count = Rails.application.middleware.middlewares.count { |m| m.klass == Rack::Attack }
    expect(count).to eq(1)
    expect(File.read(Rails.root.join("config.ru"))).not_to match(/^\s*use\s+Rack::Attack/)
  end

  it "defines the logins/ip throttle as 20 requests per hour" do
    throttle = Rack::Attack.throttles["logins/ip"]
    expect(throttle).not_to be_nil
    expect(throttle.limit).to eq(20)
    expect(throttle.period.to_i).to eq(3600)
  end

  [["/oauth/token.json", true], ["/oauth/token", false], ["/oauth/token", true]].each do |path, json|
    it "throttles password-grant POST #{path} (#{json ? 'json' : 'form'}) per IP after 20 requests" do
      first = statuses_for(path, "10.20.30.40", 20, json: json)
      expect(first).not_to include(429)
      expect(statuses_for(path, "10.20.30.40", 1, json: json)).to eq([429])
      expect(statuses_for(path, "10.20.30.41", 1, json: json)).not_to include(429)
    end
  end

  it "does not count refresh_token grants (frontend token refresh must keep working)" do
    expect(statuses_for("/oauth/token", "10.20.30.43", 25, grant_type: "refresh_token", json: true)).not_to include(429)
    expect(statuses_for("/oauth/token.json", "10.20.30.44", 25, grant_type: "refresh_token")).not_to include(429)
  end

  it "does not throttle other POST endpoints" do
    expect(statuses_for("/oauth/revoke", "10.20.30.42", 25)).not_to include(429)
  end

  it "enables Devise password-change and email-changed notifications" do
    expect(Devise.send_password_change_notification).to be(true)
    expect(Devise.send_email_changed_notification).to be(true)
  end

  def with_queue_adapter(adapter)
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    yield ActiveJob::Base.queue_adapter
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  it "accepts a password without complexity rules and mails on password and email change" do
    with_queue_adapter(:inline) do
      agent = Agent.create!(email: "probe-m1@example.com", password: "simplepassword", password_confirmation: "simplepassword")
      ActionMailer::Base.deliveries.clear

      agent.update!(password: "anotherplainpass", password_confirmation: "anotherplainpass")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["probe-m1@example.com"])

      agent.update!(email: "probe-m1-new@example.com")
      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["probe-m1@example.com"])
    end
  end

  it "enqueues the two new notifications instead of sending them inside the update transaction" do
    with_queue_adapter(:test) do |adapter|
      agent = Agent.create!(email: "probe-m1-q@example.com", password: "simplepassword", password_confirmation: "simplepassword")
      ActionMailer::Base.deliveries.clear
      adapter.enqueued_jobs.clear

      agent.update!(password: "anotherplainpass", password_confirmation: "anotherplainpass")
      agent.update!(email: "probe-m1-q-new@example.com")
      expect(ActionMailer::Base.deliveries).to be_empty
      mails = adapter.enqueued_jobs.map { |j| Array(j[:args])[0..1] }
      expect(mails).to include(["Devise::Mailer", "password_change"], ["Devise::Mailer", "email_changed"])
    end
  end

  it "keeps other Devise mails synchronous (reset password)" do
    with_queue_adapter(:test) do
      agent = Agent.create!(email: "probe-m1-r@example.com", password: "simplepassword", password_confirmation: "simplepassword")
      ActionMailer::Base.deliveries.clear
      agent.send_reset_password_instructions
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end
  end

  it "keeps client authentication required for the password grant" do
    expect(Doorkeeper.config.skip_client_authentication_for_password_grant).to be_falsey
  end

  describe "ChaskiqBoot.plugin_autoloader" do
    before do
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("DISABLE_AUTOLOAD_APPSTORE").and_return(nil)
    end

    def stub_plugins_table(exists)
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:table_exists?).and_wrap_original do |original, name|
        name.to_s == "plugins" ? exists : original.call(name)
      end
    end

    it "skips Plugin.save_all_plugins when the plugins table does not exist" do
      stub_plugins_table(false)
      expect(Plugin).not_to receive(:save_all_plugins)
      expect { ChaskiqBoot.plugin_autoloader }.to output.to_stdout
    end

    it "still calls Plugin.save_all_plugins when the plugins table exists" do
      stub_plugins_table(true)
      expect(Plugin).to receive(:save_all_plugins)
      expect { ChaskiqBoot.plugin_autoloader }.to output.to_stdout
    end
  end
end
