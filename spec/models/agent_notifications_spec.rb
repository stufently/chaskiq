# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Devise notifications", type: :model do
  def with_queue_adapter(adapter)
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    yield ActiveJob::Base.queue_adapter
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  it "enqueues password_change and email_changed instead of sending synchronously" do
    with_queue_adapter(:test) do |adapter|
      agent = Agent.create!(email: "notify-test@example.com", password: "plainpassword", password_confirmation: "plainpassword")
      ActionMailer::Base.deliveries.clear
      adapter.enqueued_jobs.clear

      agent.update!(password: "anotherplainpass", password_confirmation: "anotherplainpass")
      agent.update!(email: "notify-test-new@example.com")

      expect(ActionMailer::Base.deliveries).to be_empty
      mails = adapter.enqueued_jobs.map { |j| Array(j[:args])[0..1] }
      expect(mails).to include(["Devise::Mailer", "password_change"], ["Devise::Mailer", "email_changed"])
    end
  end

  it "delivers password_change to the agent and email_changed to the old address" do
    with_queue_adapter(:inline) do
      agent = Agent.create!(email: "notify-inline@example.com", password: "plainpassword", password_confirmation: "plainpassword")
      ActionMailer::Base.deliveries.clear

      agent.update!(password: "anotherplainpass", password_confirmation: "anotherplainpass")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["notify-inline@example.com"])

      agent.update!(email: "notify-inline-new@example.com")
      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["notify-inline@example.com"])
    end
  end

  it "accepts a password without special characters" do
    agent = Agent.new(email: "nospecial@example.com", password: "simplepassword", password_confirmation: "simplepassword")
    expect(agent).to be_valid
  end
end
