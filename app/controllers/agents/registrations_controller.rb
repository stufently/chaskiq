# frozen_string_literal: true

# app/controllers/registrations_controller.rb
module Agents
  class RegistrationsController < Devise::RegistrationsController
    before_action :check_registrable

    def new
      super
    end

    def create
      super
    end

    def update
      super
    end

    private

    def check_registrable
      redirect_to root_url unless enabled_subscriptions?
    end
  end
end
