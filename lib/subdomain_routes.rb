# frozen_string_literal: true

class SubdomainOrDomain
  def self.matches?(request)
    if (subdomains = request.subdomains) && subdomains.any?
      subdomain = subdomains.join(".")
      APP_SUBDOMAINS.exclude?(subdomain)
    end
  end
end
