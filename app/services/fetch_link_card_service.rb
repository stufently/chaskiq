# frozen_string_literal: true

# from https://framagit.org/framasoft/framapiaf/
require "oembed"

class FetchLinkCardService < BaseService
  URL_PATTERN = %r{https?://\S+}
  # Text attributes copied from an oEmbed response to the card ("" when the response lacks one).
  OEMBED_TEXT_FIELDS = %i[title author_name author_url provider_name provider_url].freeze

  def call(url)
    # Get first http/https URL that isn't local
    # url = parse_urls(status)
    return if url.nil?

    url = url.to_s

    # card = PreviewCard.where(status: status).first_or_initialize(status: status, url: url)
    card = PreviewCard.find_or_initialize_by(url: url)
    # TODO: add a TTL here
    return card if card.persisted?

    body = MessageApis::SafeDownload.fetch(url, max_bytes: 2 * 1024 * 1024)

    return unless body&.mime_type == "text/html"

    attempt_oembed(card, url) || attempt_opengraph(card, body)
  end

  private

  def parse_urls(status)
    if status.local?
      urls = status.text.match(URL_PATTERN).to_a.map { |uri| Addressable::URI.parse(uri).normalize }
    else
      html  = Nokogiri::HTML(status.text)
      links = html.css("a")
      urls  = links.map do |a|
        Addressable::URI.parse(a["href"]).normalize unless skip_link?(a)
      end.compact
    end
    urls.first
  end

  def skip_link?(a)
    # Avoid links for hashtags and mentions (microformats)
    (a["rel"].present? && a["rel"].include?("tag")) || (a["class"].present? && a["class"].include?("u-url"))
  end

  def attempt_oembed(card, url)
    provider = OEmbed::Providers.find(url)
    return unless provider

    response = provider.get(url)

    card.type = response.type
    OEMBED_TEXT_FIELDS.each do |field|
      card.public_send("#{field}=", response.respond_to?(field) ? response.public_send(field) : "")
    end
    card.width         = 0
    card.height        = 0

    attach_oembed_thumbnail(card, response)
    # card.url    = response.url
    card.width  = response.width.presence  || 0
    card.height = response.height.presence || 0
    card.html   = response.try(:html)
    # case card.type
    card.save
    card
  rescue OEmbed::NotFound
    false
  end

  def attach_oembed_thumbnail(card, response)
    return unless response.respond_to?(:thumbnail_url)

    image = begin
      download_image(response.thumbnail_url)
    rescue StandardError
      nil
    end
    card.image.attach(image) if image.present?
  end

  def attempt_opengraph(card, body)
    page = parse_card_page(body)

    card.type             = :link
    card.title            = meta_property(page, "og:title") || page.at_xpath("//title")&.content
    card.description      = meta_property(page, "og:description") || meta_property(page, "description")

    if meta_property(page, "og:image")
      image = begin
        download_image(meta_property(page, "og:image"))
      rescue StandardError
        nil
      end
      card.image.attach(image) if image.present?
    end

    return if card.title.blank?

    card.save_with_optional_image!
    card
  end

  def parse_card_page(body)
    charset = body.content_type[/;\s*charset\s*=\s*"?([^";\s]+)/i, 1]
    page = Nokogiri::HTML(body.read, encoding: charset)
    page.css("meta[content]").each do |meta|
      meta.remove_attribute("content") unless meta["content"].presence
    end
    page
  end

  def download_image(url)
    handle = MessageApis::SafeDownload.fetch(url)
    return unless handle

    file = Tempfile.new("foo-#{Time.now.to_i}", encoding: "ascii-8bit")
    file.write(handle.read)
    file.close

    ActionDispatch::Http::UploadedFile.new(
      filename: "foo-#{Time.now.to_i}.jpg",
      type: handle.mime_type,
      tempfile: file
    )
  end

  # <meta property="..." content="..."> (OpenGraph), else <meta name="..." content="...">.
  def meta_property(html, property)
    html.at_xpath("//meta[@property=\"#{property}\"]")&.attribute("content")&.value ||
      html.at_xpath("//meta[@name=\"#{property}\"]")&.attribute("content")&.value
  end
end
