# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Models style specs" do
  describe Campaign do
    describe "#delivery_progress" do
      it "returns the percentage when there are deliveries" do
        campaign = Campaign.new
        subs = double("subs")
        metrics = double("metrics")
        availables = double("availables", size: 1)
        deliveries = double("deliveries", size: 3, empty?: false)
        allow(campaign).to receive(:subscriptions).and_return(subs)
        allow(campaign).to receive(:metrics).and_return(metrics)
        allow(subs).to receive(:availables).and_return(availables)
        allow(metrics).to receive(:deliveries).and_return(deliveries)

        expect(campaign.delivery_progress).to eq(1.0 / 3.0 * 100.0)
      end

      it "returns 0 when there are no deliveries" do
        campaign = Campaign.new
        metrics = double("metrics")
        deliveries = double("deliveries", empty?: true)
        allow(campaign).to receive(:metrics).and_return(metrics)
        allow(metrics).to receive(:deliveries).and_return(deliveries)

        expect(campaign.delivery_progress).to eq(0)
      end
    end

    describe "#clone_newsletter" do
      it "appends -copy to the name" do
        campaign = Campaign.new(name: "Promo")
        cloned = double("cloned")
        allow(campaign).to receive(:deep_clone).and_return(cloned)
        allow(cloned).to receive(:name=)

        campaign.clone_newsletter

        expect(cloned).to have_received(:name=).with("Promo-copy")
      end

      it "raises NoMethodError when name is nil" do
        campaign = Campaign.new(name: nil)
        cloned = double("cloned")
        allow(campaign).to receive(:deep_clone).and_return(cloned)
        allow(cloned).to receive(:name=)

        expect { campaign.clone_newsletter }.to raise_error(NoMethodError)
      end
    end
  end

  describe AppUser do
    describe "#plan via Subscribable" do
      pro_plan = { id: "11", name: "pro", features: [] }.with_indifferent_access
      free_plan = { id: "0", name: "free", features: [] }.with_indifferent_access
      let(:plans) { [pro_plan, free_plan] }

      before do
        allow(Plan).to receive(:all).and_return(plans)
        allow(Plan).to receive(:get_by_id) { |id| plans.find { |p| p[:id].to_s == id.to_s } }
        allow(Plan).to receive(:get) { |name| plans.find { |p| p[:name] == name } }
      end

      it "returns pro plan for stripe active" do
        app = App.new
        app.stripe_subscription_status = "active"
        app.stripe_subscription_plan_id = "11"
        expect(app.plan.name).to eq("pro")
      end

      it "returns pro plan for stripe trialing" do
        app = App.new
        app.stripe_subscription_status = "trialing"
        app.stripe_subscription_plan_id = "11"
        expect(app.plan.name).to eq("pro")
      end

      it "returns pro plan for paddle active" do
        app = App.new
        app.paddle_subscription_status = "active"
        app.paddle_subscription_plan_id = "11"
        expect(app.plan.name).to eq("pro")
      end

      it "returns pro plan for paddle trialing" do
        app = App.new
        app.paddle_subscription_status = "trialing"
        app.paddle_subscription_plan_id = "11"
        expect(app.plan.name).to eq("pro")
      end

      it "returns free plan for canceled stripe" do
        app = App.new
        app.stripe_subscription_status = "canceled"
        app.stripe_subscription_plan_id = "11"
        expect(app.plan.name).to eq("free")
      end
    end
  end

  describe AppUser do
    describe "#style_class" do
      it "returns plain for passive" do
        expect(AppUser.new(state: "passive").style_class).to eq("plain")
      end

      it "returns information for subscribed" do
        expect(AppUser.new(state: "subscribed").style_class).to eq("information")
      end

      it "returns warning for unsusbscribed" do
        expect(AppUser.new(state: "unsusbscribed").style_class).to eq("warning")
      end

      it "returns nil for an unknown state" do
        expect(AppUser.new(state: "other").style_class).to be_nil
      end

      it "returns nil for nil state" do
        expect(AppUser.new(state: nil).style_class).to be_nil
      end
    end
  end

  describe ConversationPartBlock do
    describe "#create_fase" do
      let(:app) { double("app") }

      it "fills blocks schema when package has create_fase" do
        block = ConversationPartBlock.new(blocks: { "app_package" => "Zoom" })
        allow(block).to receive(:save).and_return(true)

        zoom_api_class = Class.new do
          def self.create_fase(_block_ref, _klass)
            { definitions: { "schema_key" => "value" }, values: { "data_key" => "v" } }
          end

          delegate :create_fase, to: :class
        end
        stub_const("MessageApis::Zoom::Api", zoom_api_class)

        integration = zoom_api_class.new
        allow(block).to receive(:get_package_integration).and_return(integration)

        block.create_fase(app)
        expect(block.blocks["schema"]).to eq({ "schema_key" => "value" })
      end

      it "returns nil when package class does not exist" do
        block = ConversationPartBlock.new(blocks: { "app_package" => "Csat" })
        result = block.create_fase(app)
        expect(result).to be_nil
      end
    end
  end

  describe AppPackageIntegration do
    describe "#handle_registration" do
      it "calls register_hook when API responds to register_webhook" do
        integration = AppPackageIntegration.new
        pkg = double("app_package", is_external?: false)
        allow(integration).to receive(:app_package).and_return(pkg)

        api = double("api")
        allow(api).to receive(:respond_to?).with(:register_webhook).and_return(true)
        allow(api).to receive(:respond_to?).with(:after_install).and_return(false)
        allow(integration).to receive(:message_api_klass).and_return(api)
        allow(integration).to receive(:register_hook)

        integration.send(:handle_registration)

        expect(integration).to have_received(:register_hook)
      end

      it "does not call register_hook when API is Object.new" do
        integration = AppPackageIntegration.new
        pkg = double("app_package", is_external?: false)
        allow(integration).to receive(:app_package).and_return(pkg)
        allow(integration).to receive(:message_api_klass).and_return(Object.new)
        allow(integration).to receive(:register_hook)

        integration.send(:handle_registration)

        expect(integration).not_to have_received(:register_hook)
      end

      it "does not call register_hook when API is nil" do
        integration = AppPackageIntegration.new
        pkg = double("app_package", is_external?: false)
        allow(integration).to receive(:app_package).and_return(pkg)
        allow(integration).to receive(:message_api_klass).and_return(nil)
        allow(integration).to receive(:register_hook)

        integration.send(:handle_registration)

        expect(integration).not_to have_received(:register_hook)
      end
    end
  end

  describe Event do
    describe "#trigger_webhooks" do
      let(:event) { Event.new }

      before do
        allow(OutgoingWebhookJob).to receive(:perform_later)
      end

      it "calls Events::EmailChanged.perform for email_changed action" do
        event.action = "email_changed"
        performer = double("performer")
        stub_const("Events::EmailChanged", performer)
        allow(performer).to receive(:perform)

        event.trigger_webhooks

        expect(performer).to have_received(:perform).with(event)
      end

      it "calls Events::ConversationsStarted.perform for conversations.started" do
        event.action = "conversations.started"
        performer = double("performer")
        stub_const("Events::ConversationsStarted", performer)
        allow(performer).to receive(:perform)

        event.trigger_webhooks

        expect(performer).to have_received(:perform).with(event)
      end

      it "returns nil for an unknown action" do
        event.action = "unknown.event"
        expect(event.trigger_webhooks).to be_nil
      end

      it "raises NoMethodError when action is nil" do
        event.action = nil
        expect { event.trigger_webhooks }.to raise_error(NoMethodError)
      end
    end
  end

  describe QuickReply do
    describe "#delete_translation_if_all_blank" do
      it "keeps translation when content has text for that locale" do
        app = FactoryBot.create(:app)
        qr = app.quick_replies.create!(title: "test")
        I18n.with_locale(:es) do
          qr.content = "hola"
          qr.save!
        end

        translations_before = qr.translations.where(locale: :es).count
        expect(translations_before).to be > 0
        qr.delete_translation_if_all_blank(:es)
        expect(qr.translations.where(locale: :es).count).to eq(translations_before)
      end

      it "deletes translation when content is blank for that locale" do
        app = FactoryBot.create(:app)
        qr = app.quick_replies.create!(title: "test")
        # Create an es translation with blank content
        I18n.with_locale(:es) do
          qr.content = ""
          qr.save!
        end

        count_before = qr.translations.where(locale: :es).count
        qr.delete_translation_if_all_blank(:es)
        count_after = qr.translations.where(locale: :es).count
        expect(count_after).to be < count_before
      end
    end
  end

  describe Segment do
    describe "#tagged_result with not_eq predicates" do
      it "processes all exclude tag predicates" do
        app = FactoryBot.create(:app)
        user1 = app.add_user(email: "u1@test.com", name: "User 1")
        user2 = app.add_user(email: "u2@test.com", name: "User 2")
        user1.tag_list.add("vip")
        user1.save
        user2.tag_list.add("premium")
        user2.save

        predicates = [
          { "attribute" => "tags", "comparison" => "not_eq", "value" => "vip" },
          { "attribute" => "tags", "comparison" => "not_eq", "value" => "premium" }
        ]
        segment = Segment.create!(app: app, predicates: predicates)

        result = segment.tagged_result(nil)
        # Both tagged users should be excluded
        expect(result.to_a).not_to include(user1, user2)
      end
    end
  end
end
