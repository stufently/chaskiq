# frozen_string_literal: true

module MessageApis::UiCatalog
  class Presenter
    # configure_hook: a submitted catalog button whose id is listed here answers with the response
    # its method builds, and a submitted list item (type "item") shows the definitions of its method.
    SUBMIT_RESPONSES = {
      "aaaaaaaa" => :catalog_results_response,
      "content-url" => :content_url_response
    }.freeze

    ITEM_DEFINITIONS = {
      "list-item-1" => :text_definitions,
      "list-item-4" => :single_select_definitions,
      "list-item-2" => :textarea_definitions,
      "list-item-6" => :dropdown_definitions,
      "list-item-7" => :checkbox_definitions,
      "list-item-8" => :input_definitions
    }.freeze

    # Initialize flow webhook URL
    # Sent when an app has been inserted into a conversation, message or
    # the home screen, so that you can render the app.
    def self.initialize_hook(kind:, ctx:)
      type_value = ctx.dig(:values, :type)

      if type_value == "content"
        return {
          # ctx: ctx,
          definitions: [
            {
              type: "content",
              content_url: "/internal/ui_catalog"
            }
          ]
        }
      end

      definitions = [
        {
          name: "bubu",
          label: "this is from initialize",
          type: "button",
          action: {
            type: "submit"
          }
        }
      ]

      {
        # kind: kind,
        # ctx: ctx,
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

    # Configure flow webhook URL (optional)
    # Sent when a teammate wants to use your app, so that you can show
    # them configuration options before it’s inserted. Leaving this option
    # blank will skip configuration.
    def self.configure_hook(kind:, ctx:)
      return { kind: kind, definitions: catalog_definitions } unless ctx.dig(:field, :action, :type) == "submit"

      response = SUBMIT_RESPONSES[ctx.dig(:field, :id)]
      return send(response) if response

      { kind: kind, definitions: submitted_definitions(ctx) }
    end

    # A list item wins over the name: a field that is both the "bubu" button and a known list item shows
    # the item.
    def self.submitted_definitions(ctx)
      item = ITEM_DEFINITIONS[ctx.dig(:field, :id)] if ctx.dig(:field, :type) == "item"
      return send(item) if item
      return components_list_definitions if ctx.dig(:field, :name) == "bubu"

      catalog_definitions
    end

    def self.catalog_definitions
      [

        {
          id: "aaokokaaaaaa",
          name: "bubu",
          label: "fuckya",
          type: "button",
          action: {
            type: "submit"
          },
          grid: { xs: "w-full", sm: "w-full" }
        },

        {
          id: "aaaaaaaa",
          name: "aaaa",
          label: "a real submit for ya",
          type: "button",
          action: {
            type: "submit"
          },
          grid: { xs: "w-full", sm: "w-full" }
        },

        {
          id: "content-url",
          name: "content-url",
          label: "content-url",
          type: "button",
          action: {
            type: "submit"
          }
        },

        {
          id: "sd",
          name: "alooo",
          label: "a link",
          action: {},
          type: "button",
          grid: { xs: "w-full", sm: "w-full" }
        },
        {
          name: "a",
          label: "a separator",
          action: {},
          type: "separator",
          grid: { xs: "w-full", sm: "w-full" }
        }
      ]
    end

    def self.catalog_results_response
      results = {
        foo: "bar",
        baz: "baaz"
      }

      {
        kind: "initialize",
        # ctx: ctx,
        definitions: catalog_definitions,
        results: results
      }
    end

    def self.content_url_response
      results = {
        url: "/ppupu",
        type: "content"
      }

      {
        kind: "initialize",
        definitions: [],
        results: results
      }
    end

    def self.components_list_definitions
      [
        {
          name: "api_secret",
          type: "string",
          grid: { xs: "w-full", sm: "w-full" },
          errors: { api_secret: ["what hahah"] },
          value: "enter sandsman"
        },
        {
          name: "popis",
          label: "pipopo",
          type: "button",
          action: {
            type: "submit"
          },
          grid: { xs: "w-full", sm: "w-full" }
        },
        {
          type: "list",
          disabled: false,
          items: [
            {
              type: "item",
              id: "list-item-1",
              title: "Item 1",
              action: {
                type: "submit"
              }
            },
            {
              type: "item",
              id: "list-item-4",
              title: "Item 4",
              subtitle: "With Action",
              action: {
                type: "submit"
              }
            },
            {
              type: "item",
              id: "list-item-2",
              title: "Item 2",
              subtitle: "Show Text areas",
              tertiary_text: "With Tertiary Text",
              action: {
                type: "submit"
              }
            },
            {
              type: "item",
              id: "list-item-6",
              title: "Item 6",
              subtitle: "Show dropdowns",
              tertiary_text: "With Tertiary Text",
              action: {
                type: "submit"
              }
            },
            {
              type: "item",
              id: "list-item-7",
              title: "Item 7",
              subtitle: "Checkboxes",
              tertiary_text: "With Tertiary Text",
              action: {
                type: "submit"
              }
            },
            {
              type: "item",
              id: "list-item-8",
              title: "Item 8",
              subtitle: "Inputs",
              tertiary_text: "With inputut pupx",
              action: {
                type: "submit"
              }
            }
          ]
        }
      ]
    end

    def self.text_definitions
      [
        {
          type: "text",
          text: "This is a header",
          style: "header"
        },
        {
          type: "text",
          text: "This is paragraph text. Here's a [link](https://dev.chaskiq.io/). Here's some *bold text*. Lorem ipsum.",
          style: "paragraph"
        },
        {
          type: "text",
          text: "Left aligned",
          align: "left"
        },
        {
          type: "text",
          text: "Center aligned",
          align: "center"
        },
        {
          type: "text",
          text: "Right aligned",
          align: "right"
        },

        {
          type: "data-table",
          items: [
            {
              type: "field-value",
              field: "Key",
              value: "Value 1"
            },
            {
              type: "field-value",
              field: "Key",
              value: "Value 2"
            },
            {
              type: "field-value",
              field: "Key",
              value: "Value 3 which is a very long value that will exhibit different behaviours to the other values"
            }
          ]
        },

        {
          type: "image",
          url: "https://via.placeholder.com/150",
          height: 50,
          width: 130
        },
        {
          type: "image",
          url: "https://via.placeholder.com/150",
          height: 64,
          width: 64,
          align: "left",
          rounded: true
        },

        {
          type: "image",
          url: "https://via.placeholder.com/150",
          height: 64,
          width: 64,
          align: "center",
          rounded: true
        },

        {
          type: "image",
          url: "https://via.placeholder.com/150",
          height: 64,
          width: 64,
          align: "right",
          rounded: true
        },

        {
          type: "text",
          text: "Size as *xs* is below."
        },
        {
          type: "spacer",
          size: "xs"
        },
        {
          type: "text",
          text: "Size as *s* is below."
        },
        {
          type: "spacer",
          size: "s"
        },
        {
          type: "text",
          text: "Size as *m* is below."
        },
        {
          type: "spacer",
          size: "m"
        },
        {
          type: "text",
          text: "Size as *l* is below."
        },
        {
          type: "spacer",
          size: "l"
        },
        {
          type: "text",
          text: "Size as *xl* is below."
        },
        {
          type: "spacer",
          size: "xl"
        },
        {
          type: "text",
          text: "This is the last component."
        }

      ]
    end

    def self.single_select_definitions
      [
        {
          type: "single-select",
          id: "single-select-1",
          label: "Unsaved Options",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "single-select",
          id: "single-select-2",
          label: "Pre-selected Option",
          value: "option-1",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "single-select",
          id: "single-select-3",
          label: "Saved Options",
          save_state: "saved",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "single-select",
          id: "single-select-4",
          label: "Failed Options",
          save_state: "failed",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "single-select",
          id: "single-select-5",
          label: "Disabled Options",
          disabled: true,
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "single-select",
          id: "single-select-6",
          label: "Disabled Option",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Disabled",
              disabled: true
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        }
      ]
    end

    def self.textarea_definitions
      [
        {
          type: "textarea",
          id: "textarea-1",
          label: "Normal",
          placeholder: "Enter text here..."
        },
        {
          type: "textarea",
          id: "textarea-2",
          label: "With Value",
          placeholder: "Enter text here...",
          value: "Value entered in JSON."
        },
        {
          type: "textarea",
          id: "textarea-3",
          name: "textarea-3",
          label: "Error",
          placeholder: "Enter text here...",
          value: "Value entered in JSON.",
          error: true,
          errors: { "textarea-3": ["uno error"] }
        },
        {
          type: "textarea",
          id: "textarea-4",
          label: "Disabled",
          placeholder: "Unable to enter text",
          disabled: true
        }
      ]
    end

    def self.dropdown_definitions
      [
        {
          type: "dropdown",
          id: "dropdown-1",
          label: "Unsaved Options",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "dropdown",
          id: "dropdown-2",
          label: "Pre-selected Option",
          value: "option-1",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "dropdown",
          id: "dropdown-3",
          label: "Saved Options",
          save_state: "saved",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "dropdown",
          id: "dropdown-4",
          label: "Failed Options",
          save_state: "failed",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "dropdown",
          id: "dropdown-5",
          label: "Disabled Options",
          disabled: true,
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "dropdown",
          id: "dropdown-6",
          label: "Disabled Option",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Disabled",
              disabled: true
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        }
      ]
    end

    def self.checkbox_definitions
      [
        {
          type: "checkbox",
          id: "checkbox-1",
          label: "Unsaved Options",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "checkbox",
          id: "checkbox-2",
          label: "Pre-selected Option(s)",
          value: %w[option-1 option-2],
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "checkbox",
          id: "checkbox-3",
          label: "Saved Options",
          save_state: "saved",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "checkbox",
          id: "checkbox-4",
          label: "Failed Options",
          save_state: "failed",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "checkbox",
          id: "checkbox-5",
          label: "Disabled Options",
          disabled: true,
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1"
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        },
        {
          type: "checkbox",
          id: "checkbox-6",
          label: "Disabled Option",
          options: [
            {
              type: "option",
              id: "option-1",
              text: "Option 1",
              disabled: true
            },
            {
              type: "option",
              id: "option-2",
              text: "Option 2"
            },
            {
              type: "option",
              id: "option-3",
              text: "Option 3"
            }
          ]
        }
      ]
    end

    def self.input_definitions
      [
        {
          type: "input",
          id: "unsaved-1",
          label: "Unsaved",
          placeholder: "Enter input here...",
          save_state: "unsaved"
        },
        {
          type: "input",
          id: "unsaved-2",
          label: "Unsaved (Action)",
          placeholder: "Enter input here...",
          save_state: "unsaved",
          action: {
            type: "submit"
          }
        },
        {
          type: "input",
          id: "unsaved-3",
          label: "Unsaved (Disabled)",
          placeholder: "Enter input here...",
          save_state: "unsaved",
          disabled: true,
          action: {
            type: "submit"
          }
        },
        {
          type: "input",
          id: "failed-1",
          label: "Failed",
          placeholder: "Enter input here...",
          value: "Value is given in JSON",
          save_state: "failed"
        },
        {
          type: "input",
          id: "failed-2",
          label: "Failed (Action)",
          placeholder: "Enter input here...",
          value: "Value is given in JSON",
          save_state: "failed",
          action: {
            type: "submit"
          }
        },
        {
          type: "input",
          id: "failed-3",
          label: "Failed (Disabled)",
          placeholder: "Enter input here...",
          value: "Value is given in JSON",
          save_state: "failed",
          disabled: true,
          action: {
            type: "submit"
          }
        },
        {
          type: "input",
          id: "saved-1",
          label: "Saved",
          placeholder: "Enter input here...",
          value: "Value is given in JSON",
          save_state: "saved"
        }
      ]
    end

    private_class_method :submitted_definitions, :catalog_definitions, :catalog_results_response, :content_url_response,
                         :components_list_definitions, :text_definitions, :single_select_definitions, :textarea_definitions,
                         :dropdown_definitions, :checkbox_definitions, :input_definitions

    def self.content_hook(kind:, ctx:)
      definitions = [
        {
          id: "ubu",
          name: "bubu",
          label: "this is from content and is dynamic #{Time.zone.now}",
          type: "button",
          action: {
            type: "submit"
          }
        }
      ]

      {
        definitions: definitions
      }
    end

    # Submit Sheet flow webhook URL (optional)
    # Sent when a sheet has been submitted. A sheet is an iframe you’ve loaded in the Messenger that is closed
    # and submitted when the Submit Sheets JS method is called.
    def self.sheet_view(params)
      @user = params[:user]
      @name = @user[:name]
      @email = @user[:email]

      template = ERB.new <<-SHEET_VIEW
				<html lang="en">
					<head>
						<meta charset="UTF-8">
						<meta name="viewport" content="width=device-width, initial-scale=1.0">
						<meta http-equiv="X-UA-Compatible" content="ie=edge">
						<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;600;700;800;900&display=swap" rel="stylesheet">
						<title>[Chaskiq Article]</title>

						<style>
							body {
								font-family: 'Inter', sans-serif;
							}
						</style>

					</head>

					<body>
						<div class="container">
							<div id="main-page">
								Hello my friend #{@user.to_json}
							</div>
						</div>

					</body>
				</html>
      SHEET_VIEW

      template.result(binding)
    end
  end
end
