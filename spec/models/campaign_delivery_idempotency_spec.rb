# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let!(:recipients) do
    Array.new(4) { |i| app.add_user(email: "reader#{i}@example.com") }
  end
  let(:campaign) do
    segment = app.segments.create
    FactoryBot.create(:campaign, app: app, segments: segment.predicates)
  end

  before do
    allow_any_instance_of(described_class).to receive(:apply_premailer).and_return(true)
    allow_any_instance_of(described_class).to receive(:premailer).and_return("<p>hi</p>")
    reset_email
  end

  def mail_sender_jobs
    enqueued_jobs.count { |job| job["job_class"] == "MailSenderJob" }
  end

  def ses_sender_jobs
    enqueued_jobs.count { |job| job["job_class"] == "SesSenderJob" }
  end

  def delivered_to
    ActionMailer::Base.deliveries.flat_map(&:to)
  end

  describe "#send_newsletter" do
    it "enqueues the mailing only once when launched twice" do
      campaign.send_newsletter
      campaign.send_newsletter

      expect(mail_sender_jobs).to eq(1)
      expect(campaign.reload.state).to eq("delivering")
    end

    it "enqueues once when two stale copies of the campaign are launched" do
      first = described_class.find(campaign.id)
      second = described_class.find(campaign.id)

      first.send_newsletter
      second.send_newsletter

      expect(mail_sender_jobs).to eq(1)
    end

    it "does not relaunch a campaign that was already sent" do
      campaign.update_column(:state, "sent")

      campaign.send_newsletter

      expect(mail_sender_jobs).to eq(0)
      expect(campaign.reload.state).to eq("sent")
    end

    it "launches a campaign that has not been sent yet" do
      expect(campaign.send_newsletter).to be_truthy

      expect(mail_sender_jobs).to eq(1)
    end
  end

  describe "MailSenderJob" do
    it "skips recipients that already have a send record for this campaign" do
      recipients.first.track_send(trackable: campaign)

      MailSenderJob.perform_now(campaign)

      expect(ses_sender_jobs).to eq(recipients.size - 1)
    end

    it "does nothing when a retry runs after the campaign was sent" do
      campaign.update_column(:state, "sent")

      MailSenderJob.perform_now(campaign)

      expect(ses_sender_jobs).to eq(0)
    end

    it "does not mail anyone twice when retried after a partial failure" do
      calls = 0
      allow_any_instance_of(described_class).to receive(:push_notification).and_wrap_original do |original, *args|
        calls += 1
        raise "connection lost" if calls == 3

        original.call(*args)
      end

      perform_enqueued_jobs do
        expect { MailSenderJob.perform_now(campaign) }.to raise_error("connection lost")
        expect(delivered_to.size).to eq(2)

        MailSenderJob.perform_now(campaign)
      end

      expect(delivered_to).to match_array(recipients.map(&:email))
      expect(campaign.reload.state).to eq("sent")
    end
  end

  describe "SesSenderJob" do
    it "delivers to a recipient once when the job runs twice" do
      recipient = recipients.first

      SesSenderJob.perform_now(campaign, recipient)
      SesSenderJob.perform_now(campaign, recipient)

      expect(delivered_to).to eq([recipient.email])
      expect(campaign.metrics.where(action: "send", app_user: recipient).count).to eq(1)
    end
  end

  describe "SES send notification after delivery" do
    it "keeps a single send record per recipient" do
      recipient = recipients.first
      SesSenderJob.perform_now(campaign, recipient)

      message = {
        "mail" => {
          "headers" => [
            { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s },
            { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => recipient.id.to_s }
          ]
        },
        "send" => {}
      }
      SnsReceiverJob.perform_now("send", message, nil)

      expect(campaign.metrics.where(action: "send", app_user: recipient).count).to eq(1)
    end
  end
end
