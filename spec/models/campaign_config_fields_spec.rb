# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign, "#config_fields" do
  it "returns the seven config field hashes in order with exact keys" do
    fields = I18n.with_locale(:en) { Campaign.new.config_fields }

    expect(fields).to eq([
                           {
                             name: "name",
                             label: "Campaign Name",
                             hint: "This will not be shown in the email",
                             type: "string",
                             grid: { xs: "w-full", sm: "w-full" }
                           },
                           {
                             name: "fromName",
                             label: "From Name",
                             type: "string",
                             grid: { xs: "w-full", sm: "w-1/2" }
                           },
                           {
                             name: "subject",
                             label: "Email Subject",
                             hint: "This is the email subject itself",
                             type: "text",
                             grid: { xs: "w-full", sm: "w-full" }
                           },
                           {
                             name: "description",
                             type: "textarea",
                             grid: { xs: "w-full", sm: "w-full" }
                           },
                           {
                             name: "timezone",
                             type: "timezone",
                             options: ActiveSupport::TimeZone.all.map { |o| o.tzinfo.name },
                             multiple: false,
                             grid: { xs: "w-full", sm: "w-full" }
                           },
                           {
                             name: "scheduledAt",
                             label: "Scheduled at",
                             type: "datetime",
                             grid: { xs: "w-full", sm: "w-1/2" }
                           },
                           {
                             name: "scheduledTo",
                             label: "Scheduled to",
                             type: "datetime",
                             grid: { xs: "w-full", sm: "w-1/2" }
                           }
                         ])

    expect(fields.map(&:keys)).to eq([
                                       %i[name label hint type grid],
                                       %i[name label type grid],
                                       %i[name label hint type grid],
                                       %i[name type grid],
                                       %i[name type options multiple grid],
                                       %i[name label type grid],
                                       %i[name label type grid]
                                     ])
  end
end
