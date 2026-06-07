# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationFollowUpComponent do
  # The follow-up component is a standalone appended message — it only carries
  # the outcome fields (outcome_text, outcome, resolved).

  let(:outcome_payload) do
    {
      command:      "disconnect",
      outcome:      "confirm",
      outcome_text: "Disconnected from @gmrdad82. 2 videos deleted.",
      resolved:     true
    }
  end

  it "inherits orange accent from Segment" do
    node = render_inline(described_class.new(payload: outcome_payload))
    expect(node.css("[data-accent='orange']")).not_to be_empty
  end

  it "has a surface background (var(--bg-surface))" do
    comp = described_class.new(payload: outcome_payload)
    expect(comp.background).to eq("var(--bg-surface)")
  end

  it "renders the outcome_text" do
    node = render_inline(described_class.new(payload: outcome_payload))
    expect(node.text).to include("Disconnected from @gmrdad82")
  end

  it "does NOT render a meta line (no timestamp, no handle)" do
    event = build_stubbed_event(id: 99)
    node = render_inline(described_class.new(payload: outcome_payload, event:))
    expect(node.css(".pito-echo__meta")).to be_empty
  end

  it "does NOT render body or expand detail" do
    node = render_inline(described_class.new(payload: outcome_payload))
    expect(node.css("[data-controller='pito--expand']")).to be_empty
  end

  it "renders nothing visible when outcome_text is absent" do
    node = render_inline(described_class.new(payload: { resolved: true }))
    # Component renders the segment shell but no text inside
    expect(node.css("span.text-fg").map(&:text).join).to be_blank
  end

  it "exposes dom_id when event given" do
    event = build_stubbed_event(id: 42)
    comp = described_class.new(payload: outcome_payload, event:)
    expect(comp.dom_id).to eq("event_42")
  end

  it "returns nil dom_id without event" do
    comp = described_class.new(payload: outcome_payload)
    expect(comp.dom_id).to be_nil
  end

  private

  def build_stubbed_event(id:)
    double("Event", id: id, created_at: Time.zone.now)
  end
end
