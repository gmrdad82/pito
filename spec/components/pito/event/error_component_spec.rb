# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ErrorComponent do
  describe "#initialize" do
    it "resolves the message via I18n" do
      comp = described_class.new(
        payload: {
          message_key: "pito.slash.errors.unknown_verb",
          message_args: { verb: "oops" }
        }
      )
      node = render_inline(comp)
      expect(node.css("span.text-fg").text).to include("oops")
    end

    it "interpolates message_args into the translation" do
      comp = described_class.new(
        payload: {
          message_key: "pito.slash.errors.parse_failed",
          message_args: { raw: "bad input" }
        }
      )
      node = render_inline(comp)
      expect(node.css("span.text-fg").text).to include("bad input")
    end

    it "renders text: payload directly without i18n lookup" do
      node = render_inline(described_class.new(payload: { text: "Direct error text" }))
      expect(node.css("span.text-fg").text).to include("Direct error text")
    end

    it "renders detail always-visible when detail: is present" do
      node = render_inline(described_class.new(payload: { text: "Oops", detail: "raw error detail" }))
      expect(node.text).to include("raw error detail")
    end

    it "omits detail block when no detail" do
      node = render_inline(described_class.new(payload: { text: "Simple error" }))
      expect(node.css("div.border-t")).to be_empty
    end
  end

  describe "rendered output" do
    subject(:node) do
      render_inline(described_class.new(
        payload: {
          message_key: "pito.slash.errors.unknown_verb",
          message_args: { verb: "whoops" }
        }
      ))
    end

    it "renders the error message inside span.text-fg" do
      expect(node.css("span.text-fg").text).to include("whoops")
    end

    it "renders an accent bar with data-accent='red'" do
      bar = node.css(".pito-segment__bar").first
      expect(bar).not_to be_nil
      expect(bar["data-accent"]).to eq("red")
    end

    it "renders inside the segment flex wrapper" do
      expect(node.css("div.flex").first).not_to be_nil
    end

    it "contains exactly one span.text-fg" do
      expect(node.css("span.text-fg").size).to eq(1)
    end
  end

  describe "instant render (item 18: no typewriter)" do
    subject(:node) { render_inline(described_class.new(payload: { text: "Boom" })) }

    it "renders the error instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.text).to include("Boom")
    end
  end
end
