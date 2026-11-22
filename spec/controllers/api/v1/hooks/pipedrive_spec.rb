# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  def block_actions(id:, message_data: {}, conversation: nil)
    payload = {}

    {
      "payload" => payload.to_json,
      # "app_key"=> app.key,
      # "provider"=>"pipedrive",
      "id" => id
    }
  end

  def data_for(id:, app:)
    # sent on created
    {
      "v" => 1,
      "matches_filters" => { "current" => [] },
      "meta" => JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_updated_meta.json").read),
      "current" => JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_updated_current.json").read),
      "previous" => JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_updated_previous.json").read),
      "event" => "updated.person",
      "retry" => 0,
      # "app_key"=>app.key,
      # "provider"=>"pipedrive",
      "id" => id
    }
  end

  def update_data_for(id:, app:, profile_id:)
    {
      "v" => 1,
      "matches_filters" => { "current" => [] },
      "meta" => {
        "v" => 1,
        "action" => "updated",
        "object" => "person",
        "id" => profile_id,
        "webhook_id" => "136435"
      },
      "current" => { "id" => profile_id }.merge(
        JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_renamed_current.json").read)
      ),
      "previous" => { "id" => profile_id }.merge(
        JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_renamed_previous.json").read)
      ),
      "event" => "updated.person",
      "retry" => 0,
      # "app_key"=> app.key,
      # "provider"=>"pipedrive",
      "id" => id
    }
  end

  def delete_data_for(id:, app:)
    {
      "v" => 1, "matches_filters" => { "current" => [] },
      "meta" => JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_deleted_meta.json").read),
      "current" => nil,
      "previous" => JSON.parse(Rails.root.join("spec/fixtures/requests/pipedrive/person_deleted_previous.json").read),
      "event" => "deleted.person",
      "retry" => 0,
      # "app_key"=> app.key,
      # "provider"=>"pipedrive",
      "id" => id
    }
  end

  let!(:app) do
    FactoryBot.create(:app)
  end

  let!(:visitor) do
    app.add_anonymous_user({})
  end

  let!(:user) do
    app.add_user(email: "test@test.cl")
  end

  let!(:agent_role) do
    app.add_agent({ email: "test2@test.cl" })
  end

  let(:app_package) do
    AppPackage.find_by(name: "Pipedrive")
  end

  let(:conversation) do
    app.start_conversation(
      message: { html_content: "message" },
      from: user
    )
  end

  describe "hooks" do
    before do
      AppPackagesCatalog.update_all
    end

    before :each do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false

      conversation

      allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration)
        .and_return({})

      @pkg = app.app_package_integrations.create(
        api_secret: "aaa",
        app_package: app_package
      )
    end

    it "will trigger crm registration" do
      visitor
    end

    it "receive contact" do
      allow_any_instance_of(MessageApis::Pipedrive).to receive(:enqueue_process_event).once
      post(:process_event, params: data_for(id: @pkg.encoded_id, app: app))
    end

    it "receive contact" do
      allow_any_instance_of(MessageApis::Pipedrive).to receive(:process_event).once

      expect do
        post(:process_event, params: data_for(id: @pkg.encoded_id, app: app))
        perform_enqueued_jobs
      end.to_not(change { AppUser.count }) # .by(1)
    end

    it "update profile" do
      allow_any_instance_of(MessageApis::Pipedrive).to receive(:update_app_user_profile).once
      post(:process_event, params: data_for(id: @pkg.encoded_id, app: app))
      perform_enqueued_jobs
    end

    it "delete profile" do
      allow_any_instance_of(MessageApis::Pipedrive).to receive(:delete_app_user_profile).once
      post(:process_event, params: delete_data_for(id: @pkg.encoded_id, app: app))
      perform_enqueued_jobs
    end

    describe "with external_profile" do
      before :each do
        user.external_profiles.create(profile_id: 1, provider: "pipedrive")
      end
      it "will destroy profile" do
        expect do
          post(:process_event, params: delete_data_for(id: @pkg.encoded_id, app: app))
          perform_enqueued_jobs
        end.to(change { ExternalProfile.count })
      end

      it "will update profile" do
        post(:process_event, params: update_data_for(id: @pkg.encoded_id, app: app, profile_id: 1))
        perform_enqueued_jobs
        expect(user.external_profiles.first.data).to be_present
        user.reload
        expect(user.first_name).to be_present
        expect(user.last_name).to be_present
      end
    end

    describe "model" do
      it "visitor converted" do
        perform_enqueued_jobs do
          allow_any_instance_of(MessageApis::Pipedrive).to receive(:trigger).once
          visitor.update(email: "aaa@aa.cl")
        end
      end

      # success response
      # (the body of spec/fixtures/requests/pipedrive/person_created.json)

      # error response
      # "{\"success\":false,\"error\":\"Person not found\",\"error_info\":\"Consulta developers.pipedrive.com para obtener m\\u00e1s
      #   informaci\\u00f3n sobre el API de Pipedrive.\",\"data\":null,\"additional_data\":null}"

      it "visitor converted" do
        success = Rails.root.join("spec/fixtures/requests/pipedrive/person_created.json").read

        allow_any_instance_of(MessageApis::Pipedrive::Api).to receive(:create_person)
          .and_return(JSON.parse(success))

        perform_enqueued_jobs do
          visitor.update(email: "aaa@aa.cl")
          visitor.reload
          expect(visitor.external_profiles).to be_any
          expect(visitor.external_profiles.first.provider).to be == "pipedrive"
          expect(visitor.external_profiles.first.profile_id).to be_present
          expect(visitor.external_profiles.first.data).to be_present
        end
      end

      it "visitor converted" do
        success = Rails.root.join("spec/fixtures/requests/pipedrive/person_created.json").read

        visitor.external_profiles.create(provider: "pipedrive", profile_id: 1)

        allow_any_instance_of(MessageApis::Pipedrive::Api).to receive(:create_person)
          .and_return(JSON.parse(success))

        perform_enqueued_jobs do
          visitor.update(email: "aaa@aa.cl")
          visitor.reload
          expect(visitor.external_profiles.size).to be == 1
          expect(visitor.external_profiles.first.provider).to be == "pipedrive"
          expect(visitor.external_profiles.first.profile_id).to be_present
          expect(visitor.external_profiles.first.data).to be_present
        end
      end
    end
  end
end
