# frozen_string_literal: true

module Helpers
  module Authorizator
    def doorkeeper_authorize!
      # raise "not logged user" if context[:current_user].blank?
      context[:doorkeeper_authorize].call
    end
  end
end
