# frozen_string_literal: true

class QuickReply < ApplicationRecord
  include GlobalizeAccessors

  belongs_to :app
  translates :content
  globalize_accessors attributes: %i[content]
end
