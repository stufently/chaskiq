# frozen_string_literal: true

require "nokogiri"
require "rails_helper"

RSpec.describe Dante::Renderer do
  describe "#render" do
    let(:prosemirror_data) do
      {
        content: [
          {
            type: "heading",
            attrs: { level: 1 },
            content: [{ type: "text", text: "Hello, world!" }]
          },
          {
            type: "paragraph",
            content: [
              { type: "text", text: "This is a " },
              { type: "text", marks: [{ type: "bold" }], text: "bold" },
              { type: "text", text: " text." }
            ]
          }
        ]
      }
    end

    it "renders the ProseMirror JSON data to HTML" do
      renderer = Dante::Renderer.new(raw: prosemirror_data)
      html_output = renderer.render

      parsed_html = Nokogiri::HTML(html_output)

      h1 = parsed_html.at_css("h1")
      expect(h1).not_to be_nil
      expect(h1.text).to eq("Hello, world!")

      p = parsed_html.at_css("p")
      expect(p).not_to be_nil
      expect(p.text).to eq("This is a bold text.")

      strong = parsed_html.at_css("strong")
      expect(strong).not_to be_nil
      expect(strong.text).to eq("bold")
    end

    it "renders file" do
      json = JSON.parse '{"type":"doc","content":[{"type":"paragraph"},{"type":"FileBlock","attrs":{"url":"blob:http://localhost:8080/fda338c3-79d5-4994-bb8a-8f1e6ebcfd52","src":null,"width":"","height":"","loading":true,"loading_progress":0,"caption":"caption!","direction":"center","file":{},"aspect_ratio":{"width":200,"height":200,"ratio":100}}}]}'
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render

      parsed_html = Nokogiri::HTML(html_output)

      h1 = parsed_html.at_css("a")
      expect(h1).not_to be_nil
    end

    it "renders embed" do
      json = JSON.parse Rails.root.join("spec/fixtures/requests/dante/embed_block.json").read
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render

      parsed_html = Nokogiri::HTML(html_output)
      h1 = parsed_html.at_css("a")
      expect(h1).not_to be_nil
    end

    it "renders embed" do
      json = JSON.parse Rails.root.join("spec/fixtures/requests/dante/video_block.json").read
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render
      parsed_html = Nokogiri::HTML(html_output)
      h1 = parsed_html.at_css("iframe")
      expect(h1).not_to be_nil
    end

    it "image image" do
      json = JSON.parse '{"type":"doc","content":[{"type":"ImageBlock","attrs":{"url":"https://miro.medium.com/v2/resize:fit:1400/format:webp/1*cg_wdzpS-Me6_CQyL1pHiA.jpeg","src":null,"width":1686,"height":1580,"loading":true,"loading_progress":0,"caption":"caption!","direction":"center","file":{},"aspect_ratio":{"width":1000,"height":937.129300118624,"ratio":93.7129300118624}}}]}'
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render
      parsed_html = Nokogiri::HTML(html_output)
      h1 = parsed_html.at_css("img")
      expect(h1).not_to be_nil
    end

    it "link marks" do
      json = JSON.parse Rails.root.join("spec/fixtures/requests/dante/link_marks.json").read
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render
      parsed_html = Nokogiri::HTML(html_output)
      h1 = parsed_html.at_css("a")
      expect(h1).not_to be_nil
    end

    it "link marks" do
      json = JSON.parse Rails.root.join("spec/fixtures/requests/dante/text_style_marks.json").read
      data = ActiveSupport::HashWithIndifferentAccess.new(json)

      renderer = Dante::Renderer.new(raw: data)
      html_output = renderer.render
      parsed_html = Nokogiri::HTML(html_output)
      # puts html_output
      h1 = parsed_html.at_css("p")
      expect(h1).not_to be_nil
    end

    describe "converter" do
      it "it converts" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_custom_color.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("strong")
        expect(h1).not_to be_nil
      end

      it "test styles" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_styles.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("h2")
        expect(h1).not_to be_nil
      end

      it "basic styles" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_basic_styles.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)

        # puts html
        h1 = parsed_html.at_css("h1")
        expect(h1).not_to be_nil
        h1 = parsed_html.at_css("h3")
        expect(h1).not_to be_nil
        h1 = parsed_html.at_css("h3")
        expect(h1).not_to be_nil
        # puts html
      end

      it "lists" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_lists.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("li")
        expect(h1).not_to be_nil
      end

      it "links" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_links.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render

        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("a")
        expect(h1).not_to be_nil
        # puts html
      end

      it "images" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_images.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("img")
        expect(h1).not_to be_nil
        # puts html
      end

      it "video embed" do
        draft_content = Rails.root.join("spec/fixtures/requests/dante/draft_video_embed.json").read
        data = Dante::Converter.draftjs_to_prosemirror(draft_content)
        html = Dante::Renderer.new(raw: data).render
        parsed_html = Nokogiri::HTML(html)
        h1 = parsed_html.at_css("iframe")
        expect(h1).not_to be_nil
      end
    end
  end
end
