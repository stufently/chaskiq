# frozen_string_literal: true

class ChatNotifierMailer < ApplicationMailer
  include Roadie::Rails::Mailer

  def notify(conversation_part)
    headers "X-SES-CONFIGURATION-SET" => Chaskiq::Config.get("SNS_CONFIGURATION_SET")
    headers "X-CHASKIQ-PART-ID" => conversation_part.id

    @conversation_part = conversation_part
    conversation = conversation_part.conversation
    app = conversation.app

    setup_instance_variables(app, conversation)

    message_author = conversation_part.app_user
    setup_author_variables(message_author)
    recipient = determine_recipient(message_author, conversation)

    return if skip_notification?(recipient)

    @user_id = recipient.id
    email_context = build_email_context(app, conversation, recipient)

    return if email_context.nil?

    template = select_template(recipient)
    return if skip_bot_delivery?(recipient)

    from_name_parametrized = email_context[:from_name].parameterize(separator: " ").capitalize.titleize

    @content = render_content
    return if @content.nil?

    deliver_notification(email_context, template, from_name_parametrized)
  end

  # rewrites local uploads to absolute urls
  def image_rewrite(html)
    html.gsub("/rails/active_storage/", "#{Chaskiq::Config.get('HOST')}/rails/active_storage/")
  end

  def serialized_to_html(serialized_content)
    content = JSON.parse(serialized_content)&.with_indifferent_access
    Dante::Renderer.new(raw: content).render
  rescue StandardError => e
    Rails.logger.error(e)
    Bugsnag.notify(e)
    nil
  end

  private

  def setup_instance_variables(app, conversation)
    @app_key = app.key
    @conversation_key = conversation.key
    @app_name = app.name
    @app_logo = app.logo_url
  end

  def setup_author_variables(message_author)
    @author_name = message_author.display_name || message_author.email.split("@").first
    @author_email = message_author.email
  end

  def determine_recipient(message_author, conversation)
    if message_author.is_a?(AppUser) && message_author.id == conversation.main_participant.id
      conversation.assignee
    else
      conversation.main_participant
    end
  end

  def skip_notification?(recipient)
    return true if recipient.blank?
    return true if recipient.is_a?(AppUser) && recipient.unsubscribed?

    false
  end

  def build_email_context(app, conversation, recipient)
    from_name = "#{@author_name} [#{app.name}]"
    raise "no outgoing_email_domain on app" if app.outgoing_email_domain.blank?

    crypt = URLcrypt.encode("#{app.id}+#{conversation.id}")
    from_email = "messages+#{crypt}@#{app.outgoing_email_domain}"
    email = recipient.email
    subject = "new message from #{app.name}"

    return if email.blank?

    add_email_headers(from_email, conversation)

    {
      from_email: from_email,
      email: email,
      subject: subject,
      from_name: from_name
    }
  end

  def select_template(recipient)
    recipient.is_a?(Agent) ? "agent_notify" : "notify"
  end

  def skip_bot_delivery?(recipient)
    recipient.is_a?(Agent) && recipient.bot? && !recipient.enable_deliveries
  end

  def add_email_headers(from_email, conversation)
    options = { "In-Reply-To" => from_email }

    # get previous 2 message ids
    reference_ids = conversation.messages
                                .order(id: :desc)
                                .where
                                .not(email_message_id: nil)
                                .limit(2)
                                .map(&:email_message_id)
                                .map { |o| "<#{o}>" }.join(" ")

    options.merge!("References" => reference_ids) if reference_ids.present?
    headers options
  end

  def render_content
    image_rewrite(
      serialized_to_html(@conversation_part.message.serialized_content) ||
      @conversation_part.message.html_content
    )
  rescue StandardError
    nil
  end

  def deliver_notification(email_context, template, from_name_parametrized)
    roadie_mail(from: "#{from_name_parametrized}<#{email_context[:from_email]}>",
                to: email_context[:email],
                subject: email_context[:subject],
                content_type: "text/html",
                return_path: email_context[:from_email]) do |format|
      format.html { render "chat_notifier_mailer/#{template}" }
      # format.text # assuming you want a text fallback as well
    end
  end
end
