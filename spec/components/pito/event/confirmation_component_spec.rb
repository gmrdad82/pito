# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationComponent do
  let(:body_text) { "You're about to disconnect from @gmrdad82." }

  let(:pending_payload) do
    { body: body_text, confirmation_handle: "alpha-1322", authenticated: true }
  end

  describe "orange accent" do
    it "renders data-accent='orange'" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css(".pito-segment__bar").first["data-accent"]).to eq("orange")
    end
  end

  describe "body text" do
    it "renders body: text" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css("span.text-fg").first.text).to include("@gmrdad82")
    end

    it "falls back to prompt_key i18n for legacy payloads" do
      node = render_inline(described_class.new(
        payload: { prompt_key: "pito.slash.confirm_demo.prompt" }
      ))
      expect(node.css("span.text-fg").first.text).to include("Confirm running this demo command?")
    end
  end

  describe "meta line" do
    it "shows the #handle in the meta line" do
      node = render_inline(described_class.new(payload: pending_payload))
      meta = node.css(".pito-echo__meta").first
      expect(meta.text).to include("#alpha-1322")
    end

    it "shows @all when authenticated" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css(".pito-echo__meta span.text-cyan").text).to include("@all")
    end

    it "hides @all when authenticated: false" do
      payload = pending_payload.merge(authenticated: false)
      node = render_inline(described_class.new(payload:))
      expect(node.css(".pito-echo__meta span.text-cyan")).to be_empty
    end

    it "shows no handle when confirmation_handle is absent" do
      node = render_inline(described_class.new(payload: { body: body_text }))
      expect(node.css(".pito-echo__meta").text).not_to include("#")
    end
  end

  describe "pending state (default)" do
    it "renders no processing indicator" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css(".pito-thinking")).to be_empty
    end

    it "renders no outcome section" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css(".border-t")).to be_empty
    end
  end

  describe "processing state" do
    let(:payload) { pending_payload.merge(processing: true, processing_word_index: 2) }

    it "renders the Braille thinking spinner" do
      node = render_inline(described_class.new(payload:))
      expect(node.css(".pito-thinking")).not_to be_empty
    end

    it "renders a processing word from the confirmation dictionary" do
      node = render_inline(described_class.new(payload:))
      expect(node.css(".pito-thinking__word").text).not_to be_empty
    end
  end

  describe "resolved: cancelled" do
    let(:payload) do
      pending_payload.merge(
        resolved: true,
        outcome: "cancelled",
        outcome_text: "Alright, I won't disconnect from this channel."
      )
    end

    it "renders no processing indicator" do
      node = render_inline(described_class.new(payload:))
      expect(node.css(".pito-thinking")).to be_empty
    end

    it "renders the outcome text after a hairline" do
      node = render_inline(described_class.new(payload:))
      outcome_div = node.css(".border-t").first
      expect(outcome_div).not_to be_nil
      expect(outcome_div.text).to include("won't disconnect")
    end
  end

  describe "resolved: confirmed" do
    let(:payload) do
      pending_payload.merge(
        resolved: true,
        outcome: "confirmed",
        outcome_text: "Disconnected from @gmrdad82. Deleted 42 videos."
      )
    end

    it "renders the outcome text after a hairline" do
      node = render_inline(described_class.new(payload:))
      expect(node.css(".border-t").first.text).to include("Deleted 42 videos")
    end
  end

  describe "ConfirmationFollowUpComponent" do
    it "has background: var(--bg-elevated)" do
      comp = Pito::Event::ConfirmationFollowUpComponent.new(payload: pending_payload)
      expect(comp.background).to eq("var(--bg-elevated)")
    end
  end
end
