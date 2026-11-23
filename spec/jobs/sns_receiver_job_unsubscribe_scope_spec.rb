# frozen_string_literal: true

require "rails_helper"

RSpec.describe SnsReceiverJob do
  let(:email) { "shared@example.com" }
  let(:app) { FactoryBot.create(:app) }
  let(:other_app) { FactoryBot.create(:app) }
  let!(:contact) { app.add_user(email: email) }
  let!(:other_contact) { other_app.add_user(email: email) }
  let(:campaign) { FactoryBot.create(:campaign, app: app) }
  let(:job) { described_class.new }

  def campaign_headers(recipient = contact)
    [
      { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s },
      { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => recipient.id.to_s }
    ]
  end

  def bounce(headers, emails = [email])
    {
      "mail" => { "headers" => headers },
      "bounce" => {
        "bounceType" => "Permanent",
        "bouncedRecipients" => emails.map { |e| { "emailAddress" => e } }
      }
    }
  end

  def complaint(headers, emails = [email])
    {
      "mail" => { "headers" => headers },
      "complaint" => {
        "complainedRecipients" => emails.map { |e| { "emailAddress" => e } }
      }
    }
  end

  it "unsubscribes a bounced address only in the campaign's app" do
    job.perform("bounce", bounce(campaign_headers), nil)

    expect(contact.reload).to be_unsubscribed
    expect(other_contact.reload).to be_subscribed
  end

  it "unsubscribes a complaining address only in the campaign's app" do
    job.perform("complaint", complaint(campaign_headers), nil)

    expect(contact.reload).to be_unsubscribed
    expect(other_contact.reload).to be_subscribed
  end

  it "scopes a conversation email complaint to the conversation's app" do
    conversation = other_app.start_conversation(
      message: { text_content: "hi" },
      from: other_contact
    )
    part = conversation.messages.last
    headers = [{ "name" => "X-CHASKIQ-PART-ID", "value" => part.id.to_s }]

    job.perform("complaint", complaint(headers), nil)

    expect(other_contact.reload).to be_unsubscribed
    expect(contact.reload).to be_subscribed
  end

  it "unsubscribes nobody when the notification names no app" do
    job.perform("bounce", bounce([]), nil)

    expect(contact.reload).to be_subscribed
    expect(other_contact.reload).to be_subscribed
  end

  it "keeps processing when a recipient is already unsubscribed" do
    contact.unsubscribe!
    second = app.add_user(email: "second@example.com")

    expect do
      job.perform("bounce", bounce(campaign_headers, [email, second.email]), nil)
    end.not_to raise_error

    expect(contact.reload).to be_unsubscribed
    expect(second.reload).to be_unsubscribed
  end

  it "accepts a repeated complaint for the same recipient" do
    job.perform("complaint", complaint(campaign_headers), nil)

    expect do
      job.perform("complaint", complaint(campaign_headers), nil)
    end.not_to raise_error
    expect(contact.reload).to be_unsubscribed
  end
end
