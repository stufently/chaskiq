require "mail"

module EmailValidable
  extend ActiveSupport::Concern

  class EmailValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      unless Truemail.valid?(value.to_s, with: :regex)
        record.errors.add(attribute, options[:message] || "is not an email")
      end
    end
  end
end
