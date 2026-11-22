# frozen_string_literal: true

module MessageApis
  module ContentShowcase
    class Presenter
      # Initialize flow webhook URL
      # Sent when an app has been inserted into a conversation, message or
      # the home screen, so that you can render the app.
      def self.initialize_hook(kind:, ctx:)
        if ctx.dig(:values, :article)

          record = AnnouncementRecord.new(
            heading: ctx.dig(:values, :heading)
          )

          articles = ctx.dig(:values, :article)
          # TODO: validate ?
          items = articles.map do |o|
            options = o.permit(
              :description,
              :heading,
              :page_url,
              :title,
              :cover_image
            )
            record.class.new(options)
          end

          definitions = record.article_presentation_fields(items)

          return {
            wait_for_input: false,
            definitions: definitions
          }
        end

        aa = AnnouncementRecord.new(
          ctx[:values].permit(
            :description,
            :heading,
            :page_url,
            :title,
            :cover_image
          )
        )

        definitions = aa.presentation_schema

        {
          # kind: kind,
          # ctx: ctx,
          wait_for_input: false,
          definitions: definitions
        }
      end

      # Submit flow webhook URL
      # Sent when an end-user interacts with your app, via a button,
      # link, or text input. This flow can occur multiple times as an
      # end-user interacts with your app.
      def self.submit_hook(kind:, ctx:)
        { content: { kind: kind, ctx: ctx } }

        definitions = [
          {
            type: "text",
            text: "yes!!!!!",
            style: "header"
          },
          {
            type: "text",
            text: "This is paragraph text. Here's a [link](https://dev.chaskiq.io/). Here's some *bold text*. Lorem ipsum.",
            style: "paragraph"
          }
        ]

        {
          # kind: kind,
          # ctx: ctx,
          definitions: definitions
        }
      end

      ANNOUNCEMENT_TITLE = { title: "Announcement", subtitle: "Broadcast a message" }.freeze
      TOP_ARTICLES_TITLE = { title: "Top Articles", subtitle: "Suggest helpful articles" }.freeze
      # Submit actions of configure_hook by field id; an id that only contains "autofill-" fills one
      # article of the list (configure_autofill_article).
      CONFIGURE_ACTIONS = {
        "pick-another" => :configure_pick_another,
        "announcement" => :configure_announcement,
        "top-articles" => :configure_top_articles,
        "autofill" => :configure_autofill,
        "add-to-messenger" => :configure_add_to_messenger,
        "customize-announcement" => :configure_customize_announcement,
        "customize-top-articles" => :configure_customize_top_articles,
        "add-articles-to-messenger" => :configure_add_articles_to_messenger,
        "add-new-article" => :configure_add_new_article
      }.freeze

      # Configure flow webhook URL (optional)
      # Sent when a teammate wants to use your app, so that you can show
      # them configuration options before it’s inserted. Leaving this option
      # blank will skip configuration.
      def self.configure_hook(kind:, ctx:)
        record = AnnouncementRecord.new
        if ctx.dig(:field, :action, :type) == "submit"
          response = configure_action(kind, ctx, record)
          return response if response
        end

        configure_response(kind, record.base_schema)
      end

      def self.configure_action(kind, ctx, record)
        id = ctx.dig(:field, :id)
        action = CONFIGURE_ACTIONS[id]
        return send(action, kind, ctx, record) if action

        configure_autofill_article(kind, ctx, record) if id.include?("autofill-")
      end

      def self.configure_response(kind, definitions)
        { kind: kind, definitions: definitions }
      end

      def self.initialize_response(definitions, results)
        { kind: "initialize", definitions: definitions, results: results }
      end

      def self.configure_pick_another(kind, _ctx, record)
        configure_response(kind, record.base_schema)
      end

      def self.configure_announcement(kind, _ctx, record)
        configure_response(kind, record.base_title(**ANNOUNCEMENT_TITLE) + record.customize_buttons(type: "announcement"))
      end

      def self.configure_top_articles(kind, _ctx, record)
        configure_response(kind, record.base_title(**TOP_ARTICLES_TITLE) + record.customize_buttons(type: "top-articles"))
      end

      def self.configure_autofill(kind, ctx, _record)
        configure_response(kind, autofilled_record(ctx).schema)
      end

      def self.configure_add_to_messenger(kind, ctx, _record)
        record = autofilled_record(ctx)
        return configure_response(kind, record.schema) unless record.valid?

        initialize_response(record.schema, ctx[:values])
      end

      def self.autofilled_record(ctx)
        AnnouncementRecord.new(
          description: ctx.dig(:values, :description),
          heading: ctx.dig(:values, :heading),
          page_url: ctx.dig(:values, :page_url),
          title: ctx.dig(:values, :title)
        ).tap(&:autofill)
      end

      def self.configure_customize_announcement(kind, _ctx, record)
        configure_response(kind, record.base_title(**ANNOUNCEMENT_TITLE) + record.schema)
      end

      def self.configure_customize_top_articles(kind, _ctx, record)
        configure_response(kind, record.base_title(**TOP_ARTICLES_TITLE) + record.top_articles_schema)
      end

      def self.configure_add_articles_to_messenger(kind, ctx, record)
        articles = ctx.dig(:values, "article")
        record.heading = ctx.dig(:values, "heading")
        return initialize_response([], ctx[:values]) if articles_valid?(articles)

        top_articles_response(kind, record, articles, append: false, validate: true)
      end

      def self.articles_valid?(articles)
        articles.map do |o|
          AnnouncementRecord.new(o.permit(:description, :heading, :page_url, :title, :cover_image)).valid?
        end.all?
      end

      def self.configure_add_new_article(kind, ctx, record)
        record.heading = ctx.dig(:values, "heading")
        top_articles_response(kind, record, ctx.dig(:values, "article"), append: true, validate: false)
      end

      def self.configure_autofill_article(kind, ctx, record)
        record.heading = ctx.dig(:values, "heading")
        index = ctx.dig(:field, :id).split("-").last.to_i
        top_articles_response(kind, record, ctx.dig(:values, "article"), append: false, validate: false,
                                                                         autofill_index: index)
      end

      def self.top_articles_response(kind, record, articles, **)
        fields = AnnouncementRecord.generate_collection_definitions(articles, **)
        configure_response(kind, (record.base_title(**TOP_ARTICLES_TITLE) + record.top_articles_schema(fields)).flatten)
      end

      private_class_method :configure_action, :configure_response, :initialize_response, :configure_pick_another,
                           :configure_announcement, :configure_top_articles, :configure_autofill,
                           :configure_add_to_messenger, :autofilled_record, :configure_customize_announcement,
                           :configure_customize_top_articles, :configure_add_articles_to_messenger,
                           :articles_valid?, :configure_add_new_article, :configure_autofill_article,
                           :top_articles_response

      # Submit Sheet flow webhook URL (optional)
      # Sent when a sheet has been submitted. A sheet is an iframe you’ve loaded in the Messenger that is closed
      # and submitted when the Submit Sheets JS method is called.
      def self.sheet_hook(_params)
        []
      end

      class AnnouncementRecord
        include ActiveModel::Model
        include ActiveModel::Validations

        attr_accessor :heading, :title, :page_url, :description, :cover_image

        validates :title, presence: true
        validates_format_of :page_url, with: URI::DEFAULT_PARSER.make_regexp

        def autofill
          return if (!valid? && errors[:page_url].present?) || page_url.blank?

          res = FetchLinkCardService.new.call(page_url)
          return unless res

          self.title = res.title
          self.cover_image = res.images.first[:url] if res.images.any?
          self.description = res.description
        end

        def base_title(title:, subtitle:)
          [{
            type: "text",
            text: title,
            style: "header",
            align: "center"
          },
           {
             type: "text",
             text: subtitle,
             style: "muted",
             align: "center"
           },
           {
             type: "separator"
           }]
        end

        def customize_buttons(type:)
          [
            {
              type: "button",
              id: "customize-#{type}",
              label: "Customize",
              action: {
                type: "submit"
              }
            },

            {
              type: "button",
              id: "pick-another",
              variant: "outlined",
              size: "small",
              label: "Pick another template",
              action: {
                type: "submit"
              }
            }
          ]
        end

        def base_schema
          [

            {
              type: "text",
              text: "Pick a template",
              style: "header"
            },

            {
              type: "list",
              disabled: false,
              items: [
                {
                  type: "item",
                  id: "announcement",
                  title: "Announcement",
                  subtitle: "Broadcast a new message",
                  action: {
                    type: "submit"
                  }
                },
                {
                  type: "item",
                  id: "top-articles",
                  title: "Top Articles",
                  subtitle: "Suggest helpful articles",
                  action: {
                    type: "submit"
                  }
                }
              ]
            }
          ]
        end

        def schema
          [
            {
              type: "separator"
            },
            {
              type: "input",
              name: "heading",
              label: "heading",
              placeholder: "Introduce your announcement",
              id: "heading",
              value: heading
            },
            {
              type: "separator"
            },
            {
              type: "input",
              name: "page_url",
              label: "Page url",
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "page_url",
              value: page_url,
              errors: errors[:page_url].any? ? errors[:page_url].uniq.join(", ") : nil
            },
            {
              type: "spacer",
              size: "s"
            },
            {
              type: "button",
              variant: "outlined",
              id: "autofill",
              size: "small",
              label: "autofill inputs with page details",
              action: {
                type: "submit"
              }
            },
            {
              type: "spacer",
              size: "s"
            },
            {
              type: "input",
              label: "Title (required)",
              value: title,
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "title"
            },
            {
              type: "input",
              label: "Description",
              value: description,
              placeholder: "Make a short description",
              id: "description"
            },
            {
              type: "input",
              label: "Cover image url (required)",
              value: cover_image,
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "cover_image"
            },
            {
              type: "separator"
            },
            {
              type: "button",
              size: "small",
              id: "add-to-messenger",
              label: "Add to messenger home",
              action: {
                type: "submit"
              }
            }
          ]
        end

        def top_articles_up
          [
            { type: "separator" },
            {
              type: "spacer",
              size: "sm"
            },
            {
              type: "input",
              name: "heading",
              label: "heading",
              placeholder: "Introduce your announcement",
              id: "heading",
              value: heading
            },
            {
              type: "spacer",
              size: "sm"
            },
            {
              type: "separator"
            }
          ]
        end

        def top_articles_buttons
          [
            {
              type: "button",
              size: "small",
              id: "add-new-article",
              variant: "outlined",
              label: "Add new article",
              action: {
                type: "submit"
              }
            },
            {
              type: "separator"
            },
            {
              type: "button",
              size: "small",
              id: "add-articles-to-messenger",
              label: "Add articles to messenger home",
              action: {
                type: "submit"
              }
            }
          ]
        end

        def top_articles_schema(fields = nil)
          top_articles_up + (fields || article_fields) + top_articles_buttons
        end

        def article_fields(index = 0)
          [
            {
              type: "text",
              style: "header",
              text: "Article"
            },
            {
              type: "input",
              name: "article[#{index}][page_url]",
              label: "Page url",
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "page_url",
              value: page_url,
              errors: errors[:page_url].any? ? errors[:page_url].uniq.join(", ") : nil
            },
            {
              type: "spacer",
              size: "s"
            },
            {
              type: "button",
              variant: "outlined",
              id: "autofill-#{index}",
              size: "small",
              label: "autofill inputs with page details",
              action: {
                type: "submit"
              }
            },
            {
              type: "spacer",
              size: "s"
            },
            {
              type: "input",
              label: "Title (required)",
              name: "article[#{index}][title]",
              value: title,
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "title"
            },
            {
              type: "input",
              label: "Description",
              name: "article[#{index}][description]",
              value: description,
              placeholder: "Make a short description",
              id: "description"
            },
            {
              type: "input",
              label: "Cover image url (required)",
              name: "article[#{index}][cover_image]",
              value: cover_image,
              placeholder: "e.g. https://blog.chaskiq.io",
              id: "cover_image"
            },
            {
              type: "separator"
            }
          ]
        end

        # list
        def presentation_schema
          [
            {
              type: "separator"
            },
            {
              type: "text",
              style: "header",
              text: heading
            },
            {
              type: "separator"
            },
            {
              type: "image",
              url: cover_image,
              height: 200,
              width: "100%",
              align: "center"
            },
            {
              type: "list",
              disabled: false,
              items: [
                {
                  type: "item",
                  id: "list-item-1",
                  title: title,
                  subtitle: description,
                  action: {
                    type: "url",
                    url: page_url
                  }
                }
              ]
            }
          ]
        end

        # list
        def presentation_schema_list
          [
            {
              type: "separator"
            },
            {
              type: "text",
              style: "header",
              text: heading
            },
            {
              type: "separator"
            },
            {
              type: "list",
              disabled: false,
              items: [
                {
                  type: "item",
                  id: "list-item-1",
                  title: title,
                  subtitle: description,
                  image: cover_image,
                  action: {
                    type: "url",
                    url: page_url
                  }
                }
              ]
            }
          ]
        end

        def self.generate_collection(items)
          items.map { |o| new(o) }
        end

        def self.generate_collection_definitions(items, append: false, validate: false, autofill_index: nil)
          items.map! do |o|
            o.permit(
              :description,
              :heading,
              :page_url,
              :title,
              :cover_image
            )
          end

          result = generate_collection(items)
                   .each_with_index.map do |o, i|
            o.valid? if validate
            o.autofill if autofill_index == i
            o.article_fields(i)
          end
          result += new.article_fields(result.size) if append
          result
        end

        def self.collection_presentation(items)
          items.map! do |o|
            o.permit(
              :description,
              :heading,
              :page_url,
              :title,
              :cover_image
            )
          end

          result = generate_collection(items)
                   .each_with_index.map do |o, _i|
            o
            # o.valid? #if validate
          end
          result += new.article_fields(result.size) if append
          result
        end

        def article_presentation_fields(items)
          [
            {
              type: "separator"
            },
            {
              type: "text",
              style: "header",
              text: heading
            },
            {
              type: "separator"
            },
            {
              type: "list",
              disabled: false,
              items: items.map(&:list_item)
            }
          ]
        end

        def list_item
          {
            type: "item",
            id: "list-item-1",
            title: title,
            subtitle: description,
            image: cover_image,
            action: {
              type: "url",
              url: page_url
            }
          }
        end
      end
    end
  end
end
