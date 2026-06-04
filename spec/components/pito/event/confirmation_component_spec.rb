# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationComponent do
  let(:body_text) { "You're about to disconnect from @gmrdad82." }

  let(:pending_payload) do
    { body: body_text, confirmation_handle: "alpha-1322" }
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
  end

  describe "meta line" do
    it "shows the #handle in the meta line" do
      node = render_inline(described_class.new(payload: pending_payload))
      meta = node.css(".pito-echo__meta").first
      expect(meta.text).to include("#alpha-1322")
    end

    it "does not show a channel label" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css(".pito-echo__meta span.text-cyan")).to be_empty
    end

    it "shows no handle when confirmation_handle is absent" do
      node = render_inline(described_class.new(payload: { body: body_text }))
      expect(node.css(".pito-echo__meta").text).not_to include("#")
    end
  end

  describe "expand_detail (ctrl+|)" do
    let(:payload_with_detail) do
      pending_payload.merge(expand_detail: [
        "3 videos will be deleted",
        "  Published: 2",
        "  Unlisted: 1"
      ])
    end

    it "renders the pito--expand controller" do
      node = render_inline(described_class.new(payload: payload_with_detail))
      expect(node.css("[data-controller='pito--expand']")).not_to be_empty
    end

    it "renders the detail lines in the hidden detail block" do
      node = render_inline(described_class.new(payload: payload_with_detail))
      detail = node.css("[data-pito--expand-target='detail']").first
      expect(detail.text).to include("Published: 2")
    end

    it "shows the ctrl+| hint" do
      node = render_inline(described_class.new(payload: payload_with_detail))
      expect(node.css("[data-pito--expand-target='hint']").text).to include("ctrl+|")
    end

    it "does not render expand block when no expand_detail" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css("[data-controller='pito--expand']")).to be_empty
    end

    it "does not render expand block when resolved" do
      payload = payload_with_detail.merge(resolved: true, outcome: "confirmed", outcome_text: "Done.")
      node = render_inline(described_class.new(payload:))
      expect(node.css("[data-controller='pito--expand']")).to be_empty
    end
  end

  describe "dom_id" do
    it "returns nil when no event is given" do
      comp = described_class.new(payload: pending_payload)
      expect(comp.dom_id).to be_nil
    end

    it "returns event_N when an event is given" do
      event = build_stubbed_event(id: 99)
      comp = described_class.new(payload: pending_payload, event: event)
      expect(comp.dom_id).to eq("event_99")
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
        outcome_text: "Alright, leaving @gmrdad82 connected."
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
      expect(outcome_div.text).to include("leaving @gmrdad82 connected")
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

  describe "typewriter — never on confirmation" do
    it "does NOT add the typewriter controller to the body span" do
      node = render_inline(described_class.new(payload: pending_payload))
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "ConfirmationFollowUpComponent" do
    it "has background: var(--bg-elevated)" do
      comp = Pito::Event::ConfirmationFollowUpComponent.new(payload: pending_payload)
      expect(comp.background).to eq("var(--bg-elevated)")
    end
  end

  private

  def build_stubbed_event(id:)
    double("Event", id: id, created_at: Time.zone.now)
  end
end
